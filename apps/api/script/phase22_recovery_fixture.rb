# Run only against the disposable Phase 22 database. The shell harness supplies
# PHASE22_RECOVERY_FIXTURE=1 and a dedicated PGHOST for every invocation.
abort "recovery fixture guard" unless ENV["PHASE22_RECOVERY_FIXTURE"] == "1" &&
  %w[phase22-primary phase22-recovered].include?(ENV["PGHOST"])

require "json"
require "securerandom"
stage = ARGV.fetch(0)
key = ->(name) { "phase22-recovery-#{name}" }
auction = -> { Auction.find_by!(title: "Phase 22 isolated recovery fixture") }
actor = ->(name) { User.find_by!(name: "Phase 22 #{name}") }
command = lambda do |name, who, operation, amount|
  IdempotentBidding.call(key: key.call(name), actor_id: actor.call(who).id,
    auction_id: auction.call.id, operation: operation, amount: amount)
end
snapshot = lambda do
  a = auction.call.reload
  {
    auction_id: a.id, status: a.status, closing_policy: a.closing_policy,
    increment_policy: a.increment_policy, reserve_status: a.reserve_status,
    current_price: a.current_price, leader_id: a.current_leader_id,
    winner_id: a.winner_id, ends_at: a.ends_at.iso8601(6),
    public_revision: a.public_revision,
    bids: Bid.where(auction_id: a.id).order(:sequence).pluck(:sequence, :amount, :bidder_id),
    maximum_amount: MaximumBid.find_by!(auction_id: a.id, bidder_id: actor.call("Alice").id).maximum_amount,
    idempotency: IdempotencyRecord.where(actor_id: [ actor.call("Alice").id, actor.call("Bob").id ]).count,
    outbox: OutboxEvent.where(auction_id: a.id).order(:public_revision).pluck(:public_revision, :published_at, :kafka_published_at)
  }
end
kafka_consume = lambda do |group, count|
  client = Rdkafka::Config.new(KafkaClientConfig.build.merge(
    "group.id": group, "auto.offset.reset": "earliest", "enable.auto.commit": false,
    "enable.auto.offset.store": false
  )).consumer
  service = group == KafkaAuditConsumer::GROUP ? KafkaAuditConsumer.new(consumer: client) :
    KafkaProjectionConsumer.new(consumer: client)
  results = []
  begin
    client.subscribe(KafkaOutboxPublisher::TOPIC)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    until results.size == count
      abort "Kafka consume timed out group=#{group} count=#{results.size}/#{count}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      message = client.poll(1000)
      results << service.process(message) if message
    end
  ensure
    client.close
    service.close if service.respond_to?(:close)
  end
  results
end

case stage
when "init"
  %w[Seller Alice Bob Charlie].each do |name|
    User.create!(name: "Phase 22 #{name}", login: "phase22_#{name.downcase}",
      password: SecureRandom.hex(16))
  end
  a = Auction.create_draft!(seller: actor.call("Seller"), title: "Phase 22 isolated recovery fixture",
    description: "PITR exercise", starting_price: 10_000, minimum_increment: 1_000,
    increment_policy: "stepped", reserve_price: 50_000, closing_policy: "rapid",
    starts_at: Time.current - 60, ends_at: Time.current + 3600)
  a.schedule!
  a.activate!
  puts JSON.generate(stage: stage, auction_id: a.id, public_revision: a.reload.public_revision)
when "t1"
  outcome = command.call("maximum", "Alice", "set_maximum_bid", 30_000)
  abort "T1 command failed" unless outcome.status == 200 && !outcome.replayed
  puts JSON.generate(stage: stage, snapshot: snapshot.call.except(:maximum_amount))
when "t2"
  outcome = command.call("bid", "Bob", "place_bid", 35_000)
  abort "T2 command failed" unless outcome.status == 201 && !outcome.replayed
  puts JSON.generate(stage: stage, snapshot: snapshot.call.except(:maximum_amount))
when "t3"
  outcome = command.call("lost", "Charlie", "place_bid", 60_000)
  abort "T3 command failed" unless outcome.status == 201 && !outcome.replayed
  puts JSON.generate(stage: stage, public_revision: auction.call.public_revision)
when "verify"
  state = snapshot.call
  a = auction.call
  abort "wrong recovered policy/state" unless state.slice(:status, :closing_policy, :increment_policy,
    :reserve_status, :current_price, :public_revision, :maximum_amount, :idempotency) ==
    { status: "active", closing_policy: "rapid", increment_policy: "stepped",
      reserve_status: "not_met", current_price: 35_000, public_revision: 4,
      maximum_amount: 30_000, idempotency: 2 }
  abort "deadline/leader/winner mismatch" unless a.ends_at == a.original_ends_at &&
    a.current_leader_id == actor.call("Bob").id && a.winner_id.nil?
  abort "bid sequence or T3 mismatch" unless state[:bids].map(&:first) == [ 1, 2 ] &&
    state[:bids].map { |bid| bid[1] } == [ 30_000, 35_000 ] &&
    IdempotencyRecord.where(actor_id: actor.call("Charlie").id).none?
  events = OutboxEvent.where(auction_id: a.id).order(:public_revision)
  abort "outbox mismatch" unless state[:outbox].map(&:first) == [ 1, 2, 3, 4 ] &&
    state[:outbox].all? { |row| row[1].nil? } &&
    (ENV["PHASE22_KAFKA_DRILL"] == "1" ?
      state[:outbox].map { |row| !row[2].nil? } == [ true, true, true, false ] :
      state[:outbox].all? { |row| row[2].nil? }) &&
    events.pluck(:schema_version).uniq == [ 2 ] && events.pluck(:event_id).uniq.length == 4
  before = [ Bid.where(auction_id: state[:auction_id]).count, OutboxEvent.where(auction_id: state[:auction_id]).count ]
  replay = command.call("bid", "Bob", "place_bid", 35_000)
  stored = IdempotencyRecord.find_by!(actor_id: actor.call("Bob").id, operation: "place_bid")
  abort "historical replay failed" unless replay.status == 201 && replay.replayed &&
    replay.body == stored.response_body &&
    before == [ Bid.where(auction_id: state[:auction_id]).count, OutboxEvent.where(auction_id: state[:auction_id]).count ]
  puts JSON.generate(stage: stage, snapshot: state.except(:maximum_amount),
    private_maximum_verified: true, historical_replay: true, lost_t3: true)
when "kafka_old_before"
  abort "wrong broker" unless ENV["KAFKA_BOOTSTRAP_SERVERS"] == "phase22-old-kafka:9092"
  result = KafkaOutboxPublisher.new.run_once
  abort "old pretarget publication mismatch" unless result.slice(:published, :failed) == { published: 3, failed: 0 }
  audit = kafka_consume.call(KafkaAuditConsumer::GROUP, 3)
  projection = kafka_consume.call(KafkaProjectionConsumer::GROUP, 3)
  abort "old pretarget receipt mismatch" unless audit == [ :first, :next, :next ] &&
    ConsumedKafkaEvent.where(auction_id: auction.call.id).count == 3
  puts JSON.generate(stage: stage, published: result[:published], audit: audit, projection: projection)
when "kafka_old_future"
  abort "wrong broker" unless ENV["KAFKA_BOOTSTRAP_SERVERS"] == "phase22-old-kafka:9092"
  result = KafkaOutboxPublisher.new.run_once
  abort "old future publication mismatch" unless result.slice(:published, :failed) == { published: 2, failed: 0 }
  audit = kafka_consume.call(KafkaAuditConsumer::GROUP, 2)
  projection = kafka_consume.call(KafkaProjectionConsumer::GROUP, 2)
  state = AuctionPublicProjection.new
  begin
    abort "old future Redis revision missing" unless state.read(auction.call.id).fetch("public_revision") == 5
  ensure
    state.close
  end
  puts JSON.generate(stage: stage, published: result[:published], audit: audit, projection: projection,
    redis_revision: 5, old_broker_contains_discarded_revision: true)
when "kafka_requeue"
  abort "wrong broker" unless ENV["KAFKA_BOOTSTRAP_SERVERS"] == "phase22-fresh-kafka:9092"
  abort "authority not at target" unless auction.call.public_revision == 4 &&
    OutboxEvent.where(auction_id: auction.call.id).order(:public_revision).pluck(:public_revision) == [ 1, 2, 3, 4 ]
  ids = OutboxEvent.where(auction_id: auction.call.id).pluck(:id)
  abort "unexpected outbox range" unless ids.size == 4
  changed = OutboxEvent.transaction do
    OutboxEvent.where(id: ids, domain_event_type: nil).exists? && abort("legacy outbox in recovery range")
    OutboxEvent.where(id: ids).update_all(kafka_published_at: nil, kafka_next_attempt_at: Arel.sql("clock_timestamp()"),
      published_at: nil, next_attempt_at: Arel.sql("clock_timestamp()"))
  end
  abort "requeue count mismatch" unless changed == 4
  puts JSON.generate(stage: stage, rows: changed, low_id: ids.min, high_id: ids.max)
when "kafka_fresh_replay"
  abort "wrong broker" unless ENV["KAFKA_BOOTSTRAP_SERVERS"] == "phase22-fresh-kafka:9092"
  result = KafkaOutboxPublisher.new.run_once
  abort "fresh publication mismatch" unless result.slice(:published, :failed) == { published: 4, failed: 0 }
  audit = kafka_consume.call(KafkaAuditConsumer::GROUP, 4)
  projection = kafka_consume.call(KafkaProjectionConsumer::GROUP, 4)
  expected = Api::V1::AuctionPresenter.new(auction.call).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
  state = AuctionPublicProjection.new
  begin
    redis_state = state.read(auction.call.id)
    abort "recovered Redis mismatch" unless redis_state.fetch("public_revision") == 4 && redis_state.fetch("data") == expected
  ensure
    state.close
  end
  abort "audit dedupe mismatch" unless audit == [ :duplicate, :duplicate, :duplicate, :next ] &&
    ConsumedKafkaEvent.where(auction_id: auction.call.id).count == 4 &&
    KafkaAuditEntry.where(auction_id: auction.call.id).count == 4
  abort "projection replay mismatch" unless projection == [ :stale, :stale, :stale, :duplicate ]
  reconciler = AuctionProjectionReconciler.new
  begin
    reconciliation = reconciler.check(auction.call)
    abort "reconciliation failed" unless reconciliation == :healthy
  ensure
    reconciler.close
  end
  puts JSON.generate(stage: stage, published: result[:published], audit: audit, projection: projection,
    redis_revision: redis_state.fetch("public_revision"), exact_public_state: true,
    receipt_count: 4, reconciliation: reconciliation)
when "seed"
  projection = AuctionPublicProjection.new
  begin
    result = projection.seed(auction.call)
    state = projection.read(auction.call.id)
    expected = Api::V1::AuctionPresenter.new(auction.call).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
    exact = state&.fetch("data") == expected
    abort "projection content mismatch" if result != :stale && !exact
    puts JSON.generate(stage: stage, result: result, redis_revision: state&.fetch("public_revision"), exact_public_state: exact)
  ensure
    projection.close
  end
when "delete_projection"
  require "redis_client"
  redis = RedisClient.config(url: ENV.fetch("REDIS_URL")).new_client
  begin
    deleted = redis.call("DEL", "#{AuctionPublicProjection::KEY_PREFIX}#{auction.call.id}")
    puts JSON.generate(stage: stage, deleted: deleted)
  ensure
    redis.close
  end
else
  abort "unknown stage"
end

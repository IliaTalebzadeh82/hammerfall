# PostgreSQL is the only source of desired public state. Redis is disposable.
class AuctionProjectionReconciler
  class ProjectionUnavailable < StandardError; end
  class RepairUnavailable < ProjectionUnavailable; end

  def initialize(projection: AuctionPublicProjection.new, logger: Rails.logger)
    @projection = projection
    @logger = logger
  end

  def check(auction)
    state = @projection.read(auction.id)
    return repair(auction, :missing) unless state

    # A public command may commit while the checker is reading. A fresh row
    # avoids reporting an ordinary Kafka race as an impossible future version.
    auction.reload if state.fetch("public_revision") > auction.public_revision
    revision = state.fetch("public_revision")
    return review(auction, :ahead) if revision > auction.public_revision
    return repair(auction, :stale) if revision < auction.public_revision

    expected = Api::V1::AuctionPresenter.new(auction).as_json.stringify_keys.slice(*KafkaEventCodec::DATA_KEYS)
    return review(auction, :conflicting) unless state.fetch("data") == expected

    :healthy
  rescue AuctionPublicProjection::InvalidProjection
    review(auction, :corrupt)
  rescue RedisClient::CommandError => error
    review(auction, :corrupt, error: error)
  rescue RedisClient::Error => error
    log(auction, :unavailable, error: error)
    raise ProjectionUnavailable, "Redis projection unavailable"
  end

  def close
    @projection.close
  end

  private

  def repair(auction, kind)
    log(auction, kind)
    result = @projection.seed(auction)
    case result
    when :applied, :duplicate
      log(auction, :repaired, drift: kind, write: result)
      :repaired
    when :stale
      # A concurrent Kafka delivery or another reconciler won the revision race.
      log(auction, :raced, drift: kind)
      :raced
    else
      raise "unexpected projection write result: #{result.inspect}"
    end
  rescue RedisClient::CommandError => error
    log(auction, :repair_failed, drift: kind, error: error)
    :repair_failed_review
  rescue RedisClient::Error => error
    log(auction, :repair_failed, drift: kind, error: error)
    raise RepairUnavailable, "Redis projection repair unavailable"
  end

  def review(auction, kind, error: nil)
    log(auction, :operator_review, drift: kind, error: error)
    :operator_review
  end

  def log(auction, result, drift: nil, write: nil, error: nil)
    @logger.info(JSON.generate(event: "auction_projection_reconciliation", auction_id: auction.id,
      result: result, drift: drift, write: write, error_class: error&.class&.name))
  end
end

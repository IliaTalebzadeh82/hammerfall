RSpec.shared_context "committed auction concurrency" do
  before do
    @threads = []
    @auction_ids = []
    @bidder = User.create!(name: "Concurrency bidder")
    @user_ids = [ @bidder.id ]
    expect(ApplicationRecord.connection.open_transactions).to eq(0)
  end

  after do
    @threads.each do |thread|
      thread.kill if thread.alive?
      begin
        thread.join
      rescue StandardError
        # result already surfaces worker failures; cleanup must still run.
      end
    end
    MaximumBid.where(auction_id: @auction_ids).delete_all
    Bid.where(auction_id: @auction_ids).delete_all
    Auction.where(id: @auction_ids).delete_all
    User.where(id: @user_ids).delete_all
  end

  def active_auction(**attributes)
    auction = create_auction(state: "active", **attributes)
    @auction_ids << auction.id
    auction
  end

  def worker(&operation)
    thread = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        connection.execute("SET lock_timeout = '5s'")
        begin
          operation.call(connection)
        rescue DomainError => error
          error
        ensure
          connection.execute("RESET lock_timeout")
        end
      end
    end
    thread.report_on_exception = false
    @threads << thread
    thread
  end

  def result(thread)
    raise "Worker did not finish" unless thread.join(10)
    thread.value
  end

  def take(queue)
    value = queue.pop(timeout: 10)
    raise "Barrier timed out" if value.nil?
    value
  end

  def wait_for_lock(pid)
    connection = ApplicationRecord.connection
    holder = connection.select_value("SELECT pg_backend_pid()")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    loop do
      blocked = connection.select_value("SELECT #{holder.to_i} = ANY(pg_blocking_pids(#{pid.to_i}))")
      return if blocked
      raise "Session #{pid} never waited on the holder's lock" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.005
    end
  end
end

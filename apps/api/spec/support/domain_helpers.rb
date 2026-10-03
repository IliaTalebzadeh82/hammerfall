module DomainHelpers
  def sign_in_as(user)
    return if @signed_in_user_id == user.id && @csrf_token
    user.update!(login: "test-user-#{user.id}", password: "test-password") unless user.login?
    post "/api/v1/session", params: { session: { login: user.login, password: "test-password" } },
      headers: { "X-Hammerfall-Login" => "1" }, as: :json
    raise "Test login failed: #{response.status}" unless response.status == 201
    @csrf_token = json.fetch("csrf_token")
    @signed_in_user_id = user.id
  end

  def auth_headers(extra = {})
    { "X-CSRF-Token" => @csrf_token }.merge(extra)
  end
  def auction_attributes(**overrides)
    {
      title: "Vintage camera",
      description: "A working film camera.",
      starting_price: 10_000,
      minimum_increment: 500,
      starts_at: AuctionClock.now - 60,
      ends_at: AuctionClock.now + 3600
    }.merge(overrides)
  end

  def create_auction(state: "draft", **overrides)
    auction = Auction.create_draft!(auction_attributes(**overrides))
    if %w[scheduled active closed].include?(state)
      auction.schedule!
    end
    if %w[active closed].include?(state)
      auction.activate!
    end
    expire_fixture(auction).close! if state == "closed"
    auction.cancel! if state == "cancelled"
    auction
  end

  # Fixture-only SQL: construct a historical deadline; never inject a fake clock
  # into production commands. Concurrency expiry tests instead wait for DB time.
  def deadline_fixture(auction, deadline)
    auction.update_columns(original_ends_at: deadline, ends_at: deadline)
    auction
  end

  def expire_fixture(auction)
    deadline_fixture(auction, AuctionClock.now - 1)
  end

  # Observe the real DB clock independently of the production helper so a
  # transaction-time sabotage cannot also freeze the test's waiting mechanism.
  def database_wall_time
    ApplicationRecord.connection_pool.with_connection do |connection|
      connection.uncached { connection.select_value("SELECT clock_timestamp()") }
    end
  end

  def wait_until_database_time(time)
    timeout = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 40
    while database_wall_time < time
      raise "Database clock failed to reach fixture deadline" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > timeout
      sleep 0.01
    end
  end

  def json
    response.parsed_body
  end
end

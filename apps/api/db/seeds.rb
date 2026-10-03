# Only populate demo auctions in an empty development domain. Never replace existing local data.
if Rails.env.development?
  ApplicationRecord.transaction do
    had_domain_data = User.exists? || Auction.exists? || Bid.exists?
    # Local-only identities. Never infer ownership of an existing row from its display name.
    demo_password = "hammerfall-local-demo-only"
    operator = User.find_or_create_by!(login: "demo-operator") do |user|
      user.assign_attributes(name: "Demo Operator", role: "operator", password: demo_password)
    end
    { "Demo Alice" => "demo-alice", "Demo Bob" => "demo-bob", "Demo Carol" => "demo-carol" }.each do |name, login|
      User.find_or_create_by!(login: login) do |user|
        user.assign_attributes(name: name, password: demo_password)
      end
    end
    if had_domain_data
      puts "Demo seed skipped: domain data already exists."
    else
      now = AuctionClock.now
      alice = User.find_by!(login: "demo-alice")
      bob = User.find_by!(login: "demo-bob")

      scheduled = Auction.create_draft!(seller: operator, title: "Demo: studio headphones", starting_price: 8_000,
        minimum_increment: 500, starts_at: now + 1.day, ends_at: now + 2.days)
      scheduled.schedule!

      active = Auction.create_draft!(seller: operator, title: "Demo: film camera", starting_price: 10_000,
        minimum_increment: 500, starts_at: now - 1.hour, ends_at: now + 7.days)
      active.schedule!
      active.activate!
      active.place_bid!(bidder: alice, amount: 10_000)
      active.place_bid!(bidder: bob, amount: 11_000)

      # Development fixture import: first settle real commands in an open window,
      # then import historical deadlines with explicit SQL before normal closure.
      # There is no production command with an injectable decision clock.
      closed = Auction.create_draft!(seller: operator, title: "Demo: mechanical watch", starting_price: 20_000,
        minimum_increment: 1_000, starts_at: now - 2.hours, ends_at: now + 1.hour)
      closed.schedule!
      closed.activate!
      closed.place_bid!(bidder: bob, amount: 20_000)
      closed.place_bid!(bidder: alice, amount: 22_000)
      closed.update_columns(original_ends_at: now - 1.hour, ends_at: now - 1.hour)
      closed.close!

      puts "Created 4 demo users, 3 auctions, and 4 bids."
    end
  end
else
  puts "Demo seed skipped outside development."
end

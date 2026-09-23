# Only populate an empty development domain. Never replace existing local data.
if Rails.env.development?
  ApplicationRecord.transaction do
    if User.exists? || Auction.exists? || Bid.exists?
      puts "Demo seed skipped: domain data already exists."
    else
      now = Time.current
      alice = User.create!(name: "Demo Alice")
      bob = User.create!(name: "Demo Bob")
      User.create!(name: "Demo Carol")

      scheduled = Auction.create_draft!(title: "Demo: studio headphones", starting_price: 8_000,
        minimum_increment: 500, starts_at: now + 1.day, ends_at: now + 2.days)
      scheduled.schedule!

      active = Auction.create_draft!(title: "Demo: film camera", starting_price: 10_000,
        minimum_increment: 500, starts_at: now - 1.hour, ends_at: now + 7.days)
      active.schedule!
      active.activate!
      active.place_bid!(bidder: alice, amount: 10_000)
      active.place_bid!(bidder: bob, amount: 11_000)

      # Trusted internal time arguments exercise a historical lifecycle; no HTTP
      # endpoint accepts them. created_at remains insertion metadata.
      closed = Auction.create_draft!(title: "Demo: mechanical watch", starting_price: 20_000,
        minimum_increment: 1_000, starts_at: now - 2.hours, ends_at: now - 1.hour)
      closed.schedule!(at: closed.starts_at)
      closed.activate!(at: closed.starts_at)
      closed.place_bid!(bidder: bob, amount: 20_000, at: closed.starts_at + 5.minutes)
      closed.place_bid!(bidder: alice, amount: 22_000, at: closed.starts_at + 10.minutes)
      closed.close!

      puts "Created 3 demo users, 3 auctions, and 4 bids."
    end
  end
else
  puts "Demo seed skipped outside development."
end

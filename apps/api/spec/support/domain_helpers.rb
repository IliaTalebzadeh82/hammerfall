module DomainHelpers
  def auction_attributes(**overrides)
    {
      title: "Vintage camera",
      description: "A working film camera.",
      starting_price: 10_000,
      minimum_increment: 500,
      starts_at: 1.minute.ago,
      ends_at: 1.hour.from_now
    }.merge(overrides)
  end

  def create_auction(state: "draft", **overrides)
    auction = Auction.create_draft!(auction_attributes(**overrides))
    if %w[scheduled active closed].include?(state)
      auction.schedule!(at: auction.starts_at)
    end
    if %w[active closed].include?(state)
      auction.activate!(at: auction.starts_at)
    end
    auction.close!(at: auction.ends_at) if state == "closed"
    auction.cancel! if state == "cancelled"
    auction
  end

  def json
    response.parsed_body
  end
end

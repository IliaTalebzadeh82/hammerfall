module Bidding
  # All amounts are integer EUR cents. Bands use the current visible amount,
  # not a challenger's private ceiling or the auction's starting price.
  class BidIncrementPolicy
    # Upper bound (inclusive) in cents, followed by the increment in cents.
    STEPS = [
      [ 1_000, 100 ], [ 10_000, 500 ], [ 20_000, 1_000 ],
      [ 50_000, 2_000 ], [ 100_000, 5_000 ], [ 200_000, 10_000 ],
      [ 500_000, 20_000 ], [ 1_000_000, 50_000 ],
      [ 2_000_000, 100_000 ], [ 5_000_000, 200_000 ],
      [ 10_000_000, 500_000 ], [ 20_000_000, 1_000_000 ],
      [ 50_000_000, 2_000_000 ]
    ].freeze

    def initialize(auction)
      @auction = auction
    end

    def increment_at(visible_price)
      return @auction.minimum_increment if @auction.increment_policy == "fixed"

      STEPS.find { |upper, _| visible_price <= upper }&.last || 5_000_000
    end

    def next_after(visible_price)
      visible_price + increment_at(visible_price)
    end
  end
end

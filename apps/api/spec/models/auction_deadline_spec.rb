require "rails_helper"

RSpec.describe AuctionDeadline do
  let(:finish) { Time.utc(2026, 9, 24, 21) }

  [ [ 61, 0 ], [ Rational(60_001, 1000), 0 ], [ 60, 90 ], [ 37, 90 ], [ Rational(1, 1_000_000), 90 ], [ 0, 0 ], [ -1, 0 ] ].each do |remaining, extension|
    it "adds #{extension} to the existing end with #{remaining} seconds remaining" do
      expect(described_class.extended_end(finish, finish - remaining)).to eq(finish + extension)
      expect(described_class.due?(finish, finish - remaining)).to eq(remaining <= 0)
    end
  end

  [ [ 16, 0 ], [ 15, 10 ], [ Rational(1, 1_000_000), 10 ], [ 0, 0 ], [ -1, 0 ] ].each do |remaining, extension|
    it "applies rapid closing at #{remaining} seconds remaining" do
      expect(described_class.extended_end(finish, finish - remaining, policy: ClosingPolicy.new("rapid"))).to eq(finish + extension)
      expect(described_class.due?(finish, finish - remaining)).to eq(remaining <= 0)
    end
  end
end

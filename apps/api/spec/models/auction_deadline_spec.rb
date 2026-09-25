require "rails_helper"

RSpec.describe AuctionDeadline do
  let(:finish) { Time.utc(2026, 9, 24, 21) }

  [ [ Rational(60_001, 1000), 0 ], [ 60, 90 ], [ 37, 90 ], [ Rational(1, 1_000_000), 90 ], [ 0, 0 ], [ -1, 0 ] ].each do |remaining, extension|
    it "adds #{extension} to the existing end with #{remaining} seconds remaining" do
      expect(described_class.extended_end(finish, finish - remaining)).to eq(finish + extension)
      expect(described_class.due?(finish, finish - remaining)).to eq(remaining <= 0)
    end
  end
end

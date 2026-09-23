require "rails_helper"

RSpec.describe "Development demo seeds", :domain do
  let(:seed_file) { Rails.root.join("db/seeds.rb") }

  it "creates a small consistent demo and leaves it unchanged on rerun" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    expect { load seed_file }.to output(/Created 3 demo users/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 3, 3, 4 ])
    expect(Auction.order(:id).pluck(:status)).to eq(%w[scheduled active closed])
    Auction.where(status: %w[active closed]).each do |auction|
      expect(auction.current_price).to eq(auction.leading_bid.amount)
    end
    closed = Auction.find_by!(status: "closed")
    expect(closed.winner).to eq(closed.leading_bid.bidder)
    expect { load seed_file }.to output(/skipped/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 3, 3, 4 ])
  end

  it "does not alter an existing local domain" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    User.create!(name: "Existing owner")
    expect { load seed_file }.to output(/skipped/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 1, 0, 0 ])
  end

  it "does not populate test or production environments" do
    expect { load seed_file }.to output(/outside development/).to_stdout
    expect(User.count).to eq(0)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    expect { load seed_file }.to output(/outside development/).to_stdout
    expect(User.count).to eq(0)
  end
end

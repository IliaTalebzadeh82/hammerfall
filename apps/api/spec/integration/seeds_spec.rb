require "rails_helper"

RSpec.describe "Development demo seeds", :domain do
  let(:seed_file) { Rails.root.join("db/seeds.rb") }

  it "creates a small consistent demo and leaves it unchanged on rerun" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    expect { load seed_file }.to output(/Created 4 demo users/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 4, 3, 4 ])
    expect(Auction.order(:id).pluck(:status)).to eq(%w[scheduled active closed])
    Auction.where(status: %w[active closed]).each do |auction|
      expect(auction.current_price).to eq(auction.leading_bid.amount)
    end
    closed = Auction.find_by!(status: "closed")
    expect(closed.winner).to eq(closed.leading_bid.bidder)
    expect { load seed_file }.to output(/skipped/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 4, 3, 4 ])
  end

  it "does not alter an existing local domain" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
    legacy = User.create!(name: "Demo Alice")
    existing_demo = User.create!(name: "Existing account", login: "demo-operator", role: "member",
      password: "existing-local-password")
    expect { load seed_file }.to output(/skipped/).to_stdout
    expect([ User.count, Auction.count, Bid.count ]).to eq([ 5, 0, 0 ])
    expect(legacy.reload.login).to be_nil
    expect(User.find_by!(login: "demo-alice").id).not_to eq(legacy.id)
    expect(existing_demo.reload).to have_attributes(name: "Existing account", role: "member")
    expect(existing_demo.authenticate("existing-local-password")).to eq(existing_demo)
  end

  it "does not populate test or production environments" do
    expect { load seed_file }.to output(/outside development/).to_stdout
    expect(User.count).to eq(0)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    expect { load seed_file }.to output(/outside development/).to_stdout
    expect(User.count).to eq(0)
  end
end

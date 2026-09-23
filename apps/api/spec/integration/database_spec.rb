require "rails_helper"

RSpec.describe "PostgreSQL foundation" do
  it "connects to the isolated test database using PostgreSQL" do
    connection = ActiveRecord::Base.connection

    expect(connection.adapter_name).to eq("PostgreSQL")
    expect(connection.select_value("SELECT current_database()")).to eq("hammerfall_test")
    expect(connection.select_value("SELECT 1")).to eq(1)
  end
end

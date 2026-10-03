require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  it "rejects missing and invalid session cookies" do
    expect { connect }.to have_rejected_connection
    cookies.encrypted[UserSession::COOKIE_NAME] = "forged"
    expect { connect }.to have_rejected_connection
  end

  it "identifies a user from a live shared session row" do
    user = User.create!(name: "Cable user")
    token = UserSession.issue!(user)
    cookies.encrypted[UserSession::COOKIE_NAME] = token
    connect
    expect(connection.current_user).to eq(user)
    expect(connection.session_id).to eq(UserSession.resolve(token).id)
    UserSession.resolve(token).destroy!
    expect { connect }.to have_rejected_connection
  end
end

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("RSpec must run in the test environment") unless Rails.env.test?
require "rspec/rails"
Sidekiq.testing!(:inline)
require_relative "support/domain_helpers"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.include DomainHelpers
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!
  config.before(:each, type: :request) { RateLimitStore.reset_test! }
  config.before(:each, type: :channel) { RateLimitStore.reset_test! }
end

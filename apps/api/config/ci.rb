# Run using bin/ci. PostgreSQL and PG* environment variables must be available.
CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Autoloading", "bin/rails zeitwerk:check"
  step "Test database", "env RAILS_ENV=test bin/rails db:prepare"
  step "RSpec", "env RAILS_ENV=test bundle exec rspec"
end

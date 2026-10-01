# PostgreSQL checker sabotage

The Phase 14 checker was run inside an API-container Rails transaction after
temporarily changing auction 440's `current_price` by one increment with
`update_columns`. The command loaded `script/benchmark_verify.rb` on the same
connection and caught its expected exit status 1. The checker reported
`auction 440: price/leader disagree with final bid`. The outer transaction
then rolled back. The runner verified the price equaled its original value;
a normal checker rerun found zero failures. Outputs are
`validation-checker-sabotage.json` and `validation-checker-restored.json`.

The changed value was never committed or published. No benchmark fixture was
left invalid. This proves the checker detects a visible-history/price mismatch,
not every possible historical timing defect.

The exact runner was:

```bash
docker compose exec -T -e "BENCHMARK_MANIFEST=$(cat load-tests/fixtures/20261001T134853Z-closing.json)" api bin/rails runner - <<'RUBY'
require "json"
require "stringio"
manifest = JSON.parse(ENV.fetch("BENCHMARK_MANIFEST"))
auction = Auction.find(manifest.fetch("auctions").first)
original_price = auction.current_price
captured = StringIO.new
result = nil
Auction.transaction do
  auction.update_columns(current_price: original_price + auction.minimum_increment)
  previous_stdout = $stdout
  begin
    $stdout = captured
    load Rails.root.join("script/benchmark_verify.rb").to_s
  rescue SystemExit => error
    raise unless error.status == 1
  ensure
    $stdout = previous_stdout
  end
  result = JSON.parse(captured.string)
  raise "checker did not detect price sabotage" unless result.fetch("failures").any? { |failure| failure.include?("price/leader disagree") }
  raise ActiveRecord::Rollback
end
raise "sabotage persisted" unless Auction.find(auction.id).current_price == original_price
puts JSON.generate(sabotage_detected: true, rolled_back: true, failures: result.fetch("failures"))
RUBY
```

The subsequent plain `script/benchmark_verify.rb` command with the same
manifest exited 0 and wrote `validation-checker-restored.json`.

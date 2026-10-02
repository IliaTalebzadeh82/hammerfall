# One targeted checker invocation for an isolated chaos fixture.
require "json"

auction = Auction.find(Integer(ENV.fetch("CHAOS_AUCTION_ID")))
reconciler = AuctionProjectionReconciler.new
begin
  result = reconciler.check(auction)
  puts JSON.generate(auction_id: auction.id, public_revision: auction.public_revision, result: result)
  exit(1) unless %i[repaired healthy raced].include?(result)
ensure
  reconciler.close
end

namespace :idempotency do
  desc "Prune one bounded batch of completed outcomes past DB retention time"
  task prune: :environment do
    puts "Pruned #{IdempotencyRecord.prune_expired!} expired idempotency records."
  end
end

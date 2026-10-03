namespace :user_sessions do
  desc "Prune one bounded batch of expired browser sessions"
  task prune: :environment do
    puts "Pruned #{UserSession.prune_expired!} expired sessions."
  end
end

require Rails.root.join("lib/observability/db_pool_diagnostics")

ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(Observability::DbPoolDiagnostics::Checkout)
ActiveRecord::ConnectionAdapters::ConnectionPool::Queue.prepend(Observability::DbPoolDiagnostics::Queue)

if ENV["PERFORMANCE_CPU_PROFILE"] == "true" && Rails.env.development?
  require Rails.root.join("lib/observability/cpu_profile")
  Observability::CpuProfile.watch
end

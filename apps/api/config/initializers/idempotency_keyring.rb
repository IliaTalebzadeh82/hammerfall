Rails.application.config.after_initialize do
  Idempotency::Keyring.current
end

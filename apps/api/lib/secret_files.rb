require "uri"

module SecretFiles
  PAIRS = { "DATABASE_URL_FILE" => "DATABASE_URL", "SECRET_KEY_BASE_FILE" => "SECRET_KEY_BASE",
    "RAILS_MASTER_KEY_FILE" => "RAILS_MASTER_KEY" }.freeze

  def self.load!(env: ENV)
    PAIRS.each do |file_key, value_key|
      next unless env.key?(file_key)
      raise ArgumentError, "#{file_key} conflicts with #{value_key}" if env.key?(value_key)

      path = env.fetch(file_key)
      raise ArgumentError, "#{file_key} must name a readable file" unless File.file?(path) && File.readable?(path)

      value = File.read(path).sub(/\r?\n\z/, "")
      raise ArgumentError, "#{file_key} is empty" if value.empty?
      env[value_key] = value
    end

    validate_cloud_sql!(env) if env["DATABASE_CONNECTION_MODE"] == "cloud_sql"
  end

  def self.validate_cloud_sql!(env)
    url = URI.parse(env.fetch("DATABASE_URL", ""))
    pairs = URI.decode_www_form(url.query.to_s)
    query = pairs.to_h
    ca = query["sslrootcert"]
    unless url.scheme == "postgresql" && url.host&.end_with?(".sql-psa.goog") &&
        pairs.map(&:first).uniq.length == pairs.length && query["sslmode"] == "verify-full" &&
        ca&.start_with?("/") && File.file?(ca) && File.readable?(ca)
      raise ArgumentError, "cloud_sql requires a PostgreSQL PSA DNS hostname, verify-full and readable sslrootcert"
    end
  rescue URI::InvalidURIError
    raise ArgumentError, "cloud_sql DATABASE_URL is invalid"
  end
end

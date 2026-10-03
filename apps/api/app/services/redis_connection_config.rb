require "openssl"
require "uri"

class RedisConnectionConfig
  LOCAL_URL = "redis://127.0.0.1:6379/0"

  def self.build(env: ENV)
    mode = env.fetch("REDIS_CONNECTION_MODE", "local")
    url = env.fetch("REDIS_URL", LOCAL_URL)

    case mode
    when "local"
      { url: url }
    when "disabled"
      # Kafka publisher/audit roles do not use Redis; any accidental call fails.
      { url: "redis://127.0.0.1:1/0", connect_timeout: 0.1 }
    when "tls"
      parsed = URI.parse(url)
      unless parsed.scheme == "rediss" && parsed.host && parsed.userinfo.nil?
        raise ArgumentError, "REDIS_URL must use rediss:// without embedded credentials in TLS mode"
      end

      ca_file = env.fetch("REDIS_TLS_CA_FILE", "")
      raise ArgumentError, "REDIS_TLS_CA_FILE is required and must be readable" unless File.file?(ca_file) && File.readable?(ca_file)

      config = { url: url, ssl_params: { ca_file: ca_file, verify_mode: OpenSSL::SSL::VERIFY_PEER } }
      case env.fetch("REDIS_AUTH_MODE", "")
      when "none"
        config
      when "auth"
        path = env.fetch("REDIS_PASSWORD_FILE", "")
        raise ArgumentError, "REDIS_PASSWORD_FILE is required and must be readable" unless File.file?(path) && File.readable?(path)
        password = File.read(path).sub(/\r?\n\z/, "")
        raise ArgumentError, "REDIS_PASSWORD_FILE is empty" if password.empty?
        config.merge(password: password)
      else
        raise ArgumentError, "REDIS_AUTH_MODE must be explicit in TLS mode"
      end
    else
      raise ArgumentError, "unsupported REDIS_CONNECTION_MODE"
    end
  rescue URI::InvalidURIError
    raise ArgumentError, "REDIS_URL is invalid"
  end
end

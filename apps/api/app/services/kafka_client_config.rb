class KafkaClientConfig
  LOCAL_BOOTSTRAP = "127.0.0.1:9092"

  def self.build(env: ENV)
    mode = env.fetch("KAFKA_AUTH_MODE", "local")
    bootstrap = env.fetch("KAFKA_BOOTSTRAP_SERVERS", LOCAL_BOOTSTRAP)

    case mode
    when "local"
      { "bootstrap.servers": bootstrap }
    when "google_oidc"
      raise ArgumentError, "KAFKA_BOOTSTRAP_SERVERS is required for google_oidc" if bootstrap.empty? || bootstrap == LOCAL_BOOTSTRAP

      endpoint = env.fetch("KAFKA_OAUTH_TOKEN_ENDPOINT", "")
      unless endpoint.match?(%r{\Ahttp://(?:127\.0\.0\.1|localhost):[0-9]{1,5}/?\z})
        raise ArgumentError, "KAFKA_OAUTH_TOKEN_ENDPOINT must be a loopback HTTP endpoint"
      end

      {
        "bootstrap.servers": bootstrap,
        "security.protocol": "SASL_SSL",
        "enable.ssl.certificate.verification": true,
        "ssl.endpoint.identification.algorithm": "https",
        "sasl.mechanisms": "OAUTHBEARER",
        "sasl.oauthbearer.method": "oidc",
        "sasl.oauthbearer.token.endpoint.url": endpoint,
        # Google's local auth server ignores these required librdkafka OIDC fields.
        "sasl.oauthbearer.client.id": "unused",
        "sasl.oauthbearer.client.secret": "unused"
      }
    else
      raise ArgumentError, "unsupported KAFKA_AUTH_MODE"
    end
  end
end

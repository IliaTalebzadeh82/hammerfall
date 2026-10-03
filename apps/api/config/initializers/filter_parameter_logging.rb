# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :auction, :bid, :maximum_bid, :user, :title, :description, :amount, :name, :payload, :body,
  :key_digest, :token_digest, :password_digest, :request_fingerprint, :response_body, :maximum_amount, :priority_sequence, :origin, :passw, :login, :email, :secret, :token, :csrf, :cookie, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

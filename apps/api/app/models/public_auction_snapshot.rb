# The public snapshot contract shared by Kafka and the disposable Redis view.
# It contains no bidding instruction, command identity or publisher state.
class PublicAuctionSnapshot
  class InvalidSnapshot < StandardError; end

  DATA_KEYS = %w[title description status starting_price minimum_increment starts_at original_ends_at current_price current_leader_id ends_at closed_at winner_id].freeze
  MAXIMUM_AMOUNT = 1_000_000_000_000

  def self.validate!(data)
    raise InvalidSnapshot, "invalid public fields" unless data.is_a?(Hash) && data.keys.sort == DATA_KEYS.sort
    raise InvalidSnapshot, "invalid public text" unless data["title"].is_a?(String) && data["title"].length.between?(1, 200) &&
      data["title"].match?(/[^[:space:]]/) && data["description"].is_a?(String) && data["description"].length <= 10_000
    raise InvalidSnapshot, "invalid status" unless Auction::STATES.include?(data["status"])
    raise InvalidSnapshot, "invalid public amount" unless %w[starting_price minimum_increment current_price].all? do |field|
      data[field].is_a?(Integer) && data[field].between?(1, MAXIMUM_AMOUNT)
    end
    raise InvalidSnapshot, "invalid public identity" unless %w[current_leader_id winner_id].all? do |field|
      data[field].nil? || (data[field].is_a?(Integer) && data[field].positive?)
    end

    starts_at, original_ends_at, ends_at = %w[starts_at original_ends_at ends_at].map { |field| parse_time(data[field]) }
    closed_at = parse_time(data["closed_at"]) unless data["closed_at"].nil?
    raise InvalidSnapshot, "invalid deadline" unless starts_at < original_ends_at && original_ends_at <= ends_at
    raise InvalidSnapshot, "invalid price" if data["current_price"] < data["starting_price"]
    closed = data["status"] == "closed"
    raise InvalidSnapshot, "invalid closure" unless closed == !closed_at.nil? && (!closed || closed_at >= ends_at)
    winner_valid = closed ? data["winner_id"] == data["current_leader_id"] : data["winner_id"].nil?
    raise InvalidSnapshot, "invalid winner" unless winner_valid

    data
  end

  def self.parse_time(value)
    raise InvalidSnapshot, "invalid public time" unless value.is_a?(String)
    Time.iso8601(value)
  rescue ArgumentError
    raise InvalidSnapshot, "invalid public time"
  end
  private_class_method :parse_time
end

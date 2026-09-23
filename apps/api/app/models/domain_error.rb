class DomainError < StandardError
  attr_reader :code, :details

  def initialize(code, message, details: {})
    @code = code
    @details = details
    super(message)
  end
end

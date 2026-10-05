# The persisted auction mode supplies deadline arithmetic, never the request.
class ClosingPolicy
  RULES = { "regular" => [ 60, 90 ], "rapid" => [ 15, 10 ] }.freeze

  def initialize(mode)
    @window, @extension = RULES.fetch(mode)
  end

  attr_reader :window, :extension
end

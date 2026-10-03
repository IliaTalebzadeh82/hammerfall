class AuctionPolicy
  def initialize(actor, auction = nil)
    @actor = actor
    @auction = auction
  end

  def create?
    @actor.present?
  end

  def manage?
    @actor&.operator? || (@auction&.seller_id.present? && @auction.seller_id == @actor&.id)
  end

  def transition?
    @actor&.operator?
  end
end

class OperatorActionAudit < ApplicationRecord
  belongs_to :actor, class_name: "User"
  belongs_to :auction
end

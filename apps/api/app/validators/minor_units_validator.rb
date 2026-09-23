# Reject Rails' otherwise permissive integer coercion (e.g. 100.5 -> 100).
class MinorUnitsValidator < ActiveModel::EachValidator
  MAXIMUM = 1_000_000_000_000

  def validate_each(record, attribute, _value)
    raw = record.read_attribute_before_type_cast(attribute)
    unless raw.is_a?(Integer) && raw.between?(1, MAXIMUM)
      record.errors.add(attribute, "must be an integer between 1 and #{MAXIMUM} cents")
    end
  end
end

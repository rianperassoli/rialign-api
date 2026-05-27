# Minimal PORO serializer base — no external dependency, full control over the
# JSON shape. Subclasses implement `#attributes`.
#
#   AccountSerializer.new(account).as_json
#   AccountSerializer.collection(accounts)            # => Array of hashes
class ApplicationSerializer
  def self.collection(records, **opts)
    Array(records).map { |record| new(record, **opts).as_json }
  end

  def initialize(object, **opts)
    @object = object
    @opts = opts
  end

  def as_json(*)
    attributes
  end

  private

  attr_reader :object, :opts

  # Override in subclasses.
  def attributes
    raise NotImplementedError, "#{self.class} must implement #attributes"
  end
end

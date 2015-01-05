require 'json'

module Yora
  module Message
    def serialize(msg)
      JSON.generate(msg)
    end

    def deserialize(raw, symbolized_key = true)
      msg = JSON.parse(raw, create_additions: true)
      if symbolized_key
        Hash[msg.map { |k, v| [k.to_sym, v] }]
      else
        msg
      end
    end
  end
end

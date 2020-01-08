# frozen_string_literal: true

require 'polyphony'

module Polyphony
  # HTTP imports (loaded dynamically)
  module HTTP
    auto_import(
      Agent:  './http/client/agent',
      Rack:   './http/server/rack',
      Server: './http/server'
    )
  end
end

export_default Polyphony::HTTP
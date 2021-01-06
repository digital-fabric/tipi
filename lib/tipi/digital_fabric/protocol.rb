# frozen_string_literal: true

module Tipi
  module DigitalFabric
    module Protocol
      HTTP_REQUEST = 'http_request'
      HTTP_RESPONSE = 'http_response'

      class << self
        UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
          HTTP/1.1 101 Switching Protocols
          Upgrade: websocket
          Connection: Upgrade

        HTTP

        def upgrade_response
          UPGRADE_RESPONSE
        end

        def http_request(id, req)
          { kind: HTTP_REQUEST, id: id, headers: req.headers, body: req.body }
        end

        def http_response(id, body, headers, complete: true)
          { kind: HTTP_RESPONSE, id: id, body: body, headers: headers, complete: complete }
        end
      end
    end
  end
end


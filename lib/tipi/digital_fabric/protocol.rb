# frozen_string_literal: true

module DigitalFabric
  module Protocol
    PING = 'ping'
    SHUTDOWN = 'shutdown'

    HTTP_REQUEST = 'http_request'
    HTTP_RESPONSE = 'http_response'
    HTTP_UPGRADE = 'http_upgrade'

    CONN_DATA = 'conn_data'
    CONN_CLOSE = 'conn_close'

    WS_REQUEST = 'ws_request'
    WS_RESPONSE = 'ws_response'
    WS_DATA = 'ws_data'
    WS_CLOSE = 'ws_close'

    SEND_TIMEOUT = 15
    RECV_TIMEOUT = SEND_TIMEOUT + 5

    class << self
      def ping
        { kind: PING }
      end

      def shutdown
        { kind: SHUTDOWN }
      end

      DF_UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
        HTTP/1.1 101 Switching Protocols
        Upgrade: df
        Connection: Upgrade

      HTTP

      def df_upgrade_response
        DF_UPGRADE_RESPONSE
      end

      def http_request(id, req)
        { kind: HTTP_REQUEST, id: id, headers: req.headers, body: req.body }
      end

      def http_response(id, body, headers, complete)
        { kind: HTTP_RESPONSE, id: id, body: body, headers: headers, complete: complete }
      end

      def http_upgrade(id, headers)
        { kind: HTTP_UPGRADE, id: id }
      end

      def connection_data(id, data)
        { kind: CONN_DATA, id: id, data: data }
      end

      def connection_close(id)
        { kind: CONN_CLOSE, id: id }
      end

      def ws_request(id, headers)
        { kind: WS_REQUEST, id: id, headers: headers }
      end

      def ws_response(id, headers)
        { kind: WS_RESPONSE, id: id, headers: headers }
      end

      def ws_data(id, data)
        { id: id, kind: WS_DATA, data: data }
      end
        
      def ws_close(id)
        { id: id, kind: WS_CLOSE }
      end
    end
  end
end

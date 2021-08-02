# frozen_string_literal: true

module DigitalFabric
  module Protocol
    PING = 'ping'
    SHUTDOWN = 'shutdown'
    UNMOUNT = 'unmount'

    HTTP_REQUEST = 'http_request'
    HTTP_RESPONSE = 'http_response'
    HTTP_UPGRADE = 'http_upgrade'
    HTTP_GET_REQUEST_BODY = 'http_get_request_body'
    HTTP_REQUEST_BODY = 'http_request_body'

    CONN_DATA = 'conn_data'
    CONN_CLOSE = 'conn_close'

    WS_REQUEST = 'ws_request'
    WS_RESPONSE = 'ws_response'
    WS_DATA = 'ws_data'
    WS_CLOSE = 'ws_close'

    TRANSFER_COUNT = 'transfer_count'

    STATS_REQUEST = 'stats_request'
    STATS_RESPONSE = 'stats_response'

    SEND_TIMEOUT = 15
    RECV_TIMEOUT = SEND_TIMEOUT + 5

    module Attribute
      KIND = 0
      ID = 1

      module HttpRequest
        HEADERS = 2
        BODY_CHUNK = 3
        COMPLETE = 4
      end

      module HttpResponse
        BODY = 2
        HEADERS = 3
        COMPLETE = 4
        TRANSFER_COUNT_KEY = 5
      end

      module HttpUpgrade
        HEADERS = 2
      end

      module HttpGetRequestBody
        LIMIT = 2
      end

      module HttpRequestBody
        BODY = 2
        COMPLETE = 3
      end

      module ConnectionData
        DATA = 2
      end

      module WS
        HEADERS = 2
        DATA = 2
      end

      module TransferCount
        KEY = 1
        RX = 2
        TX = 3
      end

      module Stats
        STATS = 2
      end
    end

    class << self
      def ping
        [ PING ]
      end

      def shutdown
        [ SHUTDOWN ]
      end

      def unmount
        [ UNMOUNT ]
      end

      DF_UPGRADE_RESPONSE = <<~HTTP.gsub("\n", "\r\n")
        HTTP/1.1 101 Switching Protocols
        Upgrade: df
        Connection: Upgrade

      HTTP

      def df_upgrade_response
        DF_UPGRADE_RESPONSE
      end

      def http_request(id, headers, buffered_chunk, complete)
        [ HTTP_REQUEST, id, headers, buffered_chunk, complete ]
      end

      def http_response(id, body, headers, complete, transfer_count_key = nil)
        [ HTTP_RESPONSE, id, body, headers, complete, transfer_count_key ]
      end

      def http_upgrade(id, headers)
        [ HTTP_UPGRADE, id, headers ]
      end

      def http_get_request_body(id, limit = nil)
        [ HTTP_GET_REQUEST_BODY, id, limit ]
      end

      def http_request_body(id, body, complete)
        [ HTTP_REQUEST_BODY, id, body, complete ]
      end

      def connection_data(id, data)
        [ CONN_DATA, id, data ]
      end

      def connection_close(id)
        [ CONN_CLOSE, id ]
      end

      def ws_request(id, headers)
        [ WS_REQUEST, id, headers ]
      end

      def ws_response(id, headers)
        [ WS_RESPONSE, id, headers ]
      end

      def ws_data(id, data)
        [ WS_DATA, id, data ]
      end
        
      def ws_close(id)
        [ WS_CLOSE, id ]
      end

      def transfer_count(key, rx, tx)
        [ TRANSFER_COUNT, key, rx, tx ]
      end

      def stats_request(id)
        [ STATS_REQUEST, id ]
      end

      def stats_response(id, stats)
        [ STATS_RESPONSE, id, stats ]
      end
    end
  end
end

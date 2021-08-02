# frozen_string_literal: true

require_relative './protocol'

module DigitalFabric
  class RequestAdapter
    def initialize(agent, msg)
      @agent = agent
      @id = msg[Protocol::Attribute::ID]
    end

    def protocol
      'df'
    end

    def get_body_chunk(request)
      @agent.get_http_request_body(@id, 1)
    end

    def respond(request, body, headers)
      @agent.send_df_message(
        Protocol.http_response(@id, body, headers, true)
      )
    end

    def send_headers(request, headers, opts = {})
      @agent.send_df_message(
        Protocol.http_response(@id, nil, headers, false)
      )
  end

    def send_chunk(request, body, done: )
      @agent.send_df_message(
        Protocol.http_response(@id, body, nil, done)
      )
    end

    def finish(request)
      @agent.send_df_message(
        Protocol.http_response(@id, nil, nil, true)
      )
    end
  end
end

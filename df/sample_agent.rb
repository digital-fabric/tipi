# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'
require 'tipi/digital_fabric/protocol'
require 'tipi/digital_fabric/agent'

Protocol = DigitalFabric::Protocol

class SampleAgent < DigitalFabric::Agent
  HTML_WS = IO.read(File.join(__dir__, 'ws_page.html'))
  HTML_SSE = IO.read(File.join(__dir__, 'sse_page.html'))

  def http_request(req)
    path = req['headers'][':path']
    case path
    when '/agent'
      send_df_message(Protocol.http_response(
        req['id'],
        'Hello, world!',
        {},
        true
      ))
    when '/agent/ws'
      send_df_message(Protocol.http_response(
        req['id'],
        HTML_WS,
        { 'Content-Type' => 'text/html' },
        true
      ))
    when '/agent/sse'
      send_df_message(Protocol.http_response(
        req['id'],
        HTML_SSE,
        { 'Content-Type' => 'text/html' },
        true
      ))
    when '/agent/sse/events'
      stream_sse_response(req)
    else
      send_df_message(Protocol.http_response(
        req['id'],
        nil,
        { ':status' => 400 },
        true
      ))
    end
  
  end

  def ws_request(req)
    send_df_message(Protocol.ws_response(req['id'], {}))

    10.times do
      sleep 1
      send_df_message(Protocol.ws_data(req['id'], Time.now.to_s))
    end
    send_df_message(Protocol.ws_close(req['id']))
  end

  def stream_sse_response(req)
    send_df_message(Protocol.http_response(
      req['id'],
      nil,
      { 'Content-Type' => 'text/event-stream' },
      false
    ))
    10.times do
      sleep 1
      send_df_message(Protocol.http_response(
        req['id'],
        "data: #{Time.now}\n\n",
        nil,
        false
      ))
    end
    send_df_message(Protocol.http_response(
      req['id'],
      "retry: 0\n\n",
      nil,
      true
    ))
  end
  
end

agent = SampleAgent.new('127.0.0.1', 4411, { path: '/agent' })
agent.run

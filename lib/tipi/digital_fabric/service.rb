# frozen_string_literal: true

require_relative './protocol'
require_relative './agent_proxy'
require 'securerandom'

module DigitalFabric
  class Service
    attr_reader :token
    attr_reader :timer

    def initialize(token: )
      @token = token
      @agents = {}
      @routes = {}
      @counters = {
        connections: 0,
        http_requests: 0,
        errors: 0
      }
      @connection_count = 0
      @current_request_count = 0
      @http_latency_accumulator = 0
      @http_latency_counter = 0
      @http_latency_max = 0
      @last_counters = @counters.merge(stamp: Time.now.to_f - 1)
      @fiber = Fiber.current
      # @timer = Polyphony::Timer.new('service_timer', resolution: 5)
    end

    def calculate_stats
      now = Time.now.to_f
      elapsed = now - @last_counters[:stamp]
      connections = @counters[:connections] - @last_counters[:connections]
      http_requests = @counters[:http_requests] - @last_counters[:http_requests]
      errors = @counters[:errors] - @last_counters[:errors]
      @last_counters = @counters.merge(stamp: now)

      average_latency = @http_latency_counter == 0 ? 0 :
                        @http_latency_accumulator / @http_latency_counter
      @http_latency_accumulator = 0
      @http_latency_counter = 0
      max_latency = @http_latency_max
      @http_latency_max = 0

      cpu, rss = pid_cpu_and_rss(Process.pid)

      backend_stats = Thread.backend.stats
      op_rate = backend_stats[:op_count] / elapsed
      switch_rate = backend_stats[:switch_count] / elapsed
      poll_rate = backend_stats[:poll_count] / elapsed

      {
        service: {
          agent_count: @agents.size,
          connection_count: @connection_count,
          connection_rate: connections / elapsed,
          error_rate: errors / elapsed,
          http_request_rate: http_requests / elapsed,
          latency_avg: average_latency,
          latency_max: max_latency,
          pending_requests: @current_request_count,
          },
        backend: {
          op_rate: op_rate,
          pending_ops: backend_stats[:pending_ops],
          poll_rate: poll_rate,
          runqueue_size: backend_stats[:runqueue_size],
          runqueue_high_watermark: backend_stats[:runqueue_max_length],
          switch_rate: switch_rate,

        },
        process: {
          cpu_usage: cpu,
          rss: rss.to_f / 1024,
        }
      }
    end

    def pid_cpu_and_rss(pid)
      s = `ps -p #{pid} -o %cpu,rss`
      cpu, rss = s.lines[1].chomp.strip.split(' ')
      [cpu.to_f, rss.to_i]
    rescue Polyphony::BaseException
      raise
    rescue Exception
      [nil, nil]
    end
    
    def get_stats
      calculate_stats
    end

    def incr_connection_count
      @connection_count += 1
    end

    def decr_connection_count
      @connection_count -= 1
    end

    attr_reader :stats

    def total_request_count
      count = 0
      @agents.keys.each do |agent|
        if agent.respond_to?(:current_request_count)
          count += agent.current_request_count
        end
      end
      count
    end

    def record_latency_measurement(latency, req)
      @http_latency_accumulator += latency
      @http_latency_counter += 1
      @http_latency_max = latency if latency > @http_latency_max
      return if latency < 1.0

      puts format('slow request (%.1f): %p', latency, req.headers)
    end
  
    def http_request(req, allow_df_upgrade = false)
      @current_request_count += 1
      @counters[:http_requests] += 1
      @counters[:connections] += 1 if req.headers[':first']

      return upgrade_request(req, allow_df_upgrade) if req.upgrade_protocol
 
      inject_request_headers(req)
      agent = find_agent(req)
      unless agent
        @counters[:errors] += 1
        return req.respond(nil, ':status' => Qeweney::Status::SERVICE_UNAVAILABLE)
      end

      agent.http_request(req)
    rescue IOError, SystemCallError, HTTP2::Error::StreamClosed
      @counters[:errors] += 1
    rescue => e
      @counters[:errors] += 1
      puts '*' * 40
      p req
      p e
      puts e.backtrace.join("\n")
      req.respond(e.inspect, ':status' => Qeweney::Status::INTERNAL_SERVER_ERROR)
    ensure
      @current_request_count -= 1
      req.adapter.conn.close if @shutdown
    end

    def inject_request_headers(req)
      req.headers['x-request-id'] = SecureRandom.uuid
      conn = req.adapter.conn
      req.headers['x-forwarded-for'] = conn.peeraddr(false)[2]
      req.headers['x-forwarded-proto'] ||= conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
    end
  
    def upgrade_request(req, allow_df_upgrade)
      case (protocol = req.upgrade_protocol)
      when 'df'
        if allow_df_upgrade
          df_upgrade(req)
        else
          req.respond(nil, ':status' => Qeweney::Status::SERVICE_UNAVAILABLE)
        end
      else
        agent = find_agent(req)
        unless agent
          @counters[:errors] += 1
          return req.respond(nil, ':status' => Qeweney::Status::SERVICE_UNAVAILABLE)
        end

        agent.http_upgrade(req, protocol)
      end
    end
  
    def df_upgrade(req)
      # we don't want to count connected agents
      @current_request_count -= 1
      if req.headers['df-token'] != @token
        return req.respond(nil, ':status' => Qeweney::Status::FORBIDDEN)
      end

      req.adapter.conn << Protocol.df_upgrade_response
      AgentProxy.new(self, req)
    ensure
      @current_request_count += 1
    end
  
    def mount(route, agent)
      if route[:path]
        route[:path_regexp] = path_regexp(route[:path])
      end
      @executive = agent if route[:executive]
      @agents[agent] = route
      @routing_changed = true
    end
  
    def unmount(agent)
      route = @agents[agent]
      return unless route

      @executive = nil if route[:executive]
      @agents.delete(agent)
      @routing_changed = true
    end

    INVALID_HOST = 'INVALID_HOST'
    
    def find_agent(req)
      compile_agent_routes if @routing_changed

      host = req.headers[':authority'] || req.headers['host'] || INVALID_HOST
      path = req.headers[':path']

      route = @route_keys.find do |route|
        (host == route[:host]) || (path =~ route[:path_regexp])
      end
      return @routes[route] if route

      nil
    end

    def compile_agent_routes
      @routing_changed = false

      @routes.clear
      @agents.keys.reverse.each do |agent|
        route = @agents[agent]
        @routes[route] ||= agent
      end
      @route_keys = @routes.keys
    end

    def path_regexp(path)
      /^#{path}/
    end

    def graceful_shutdown
      @shutdown = true
      @agents.keys.each do |agent|
        if agent.respond_to?(:send_shutdown)
          agent.send_shutdown
        else
          @agents.delete(agent)
        end
      end
      move_on_after(60) do
        while !@agents.empty?
          sleep 0.25
        end
      end
    end
  end
end

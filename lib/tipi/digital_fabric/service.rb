# frozen_string_literal: true

require_relative './protocol'
require_relative './agent_proxy'

module Tipi::DigitalFabric
  class Service
    attr_reader :token

    def initialize(token: )
      @token = token
      @agents = {}
      @routes = {}
      @counters = {
        http_requests: 0,
        errors: 0
      }
      @http_latency_accumulator = 0
      @http_latency_counter = 0
      @last_counters = @counters.merge(stamp: Time.now.to_f - 1)
      update_stats
      stats_updater = spin_loop(interval: 10) { update_stats }
      @current_request_count = 0
    end

    def update_stats
      now = Time.now.to_f
      elapsed = now - @last_counters[:stamp]
      http_requests = @counters[:http_requests] - @last_counters[:http_requests]
      errors = @counters[:errors] - @last_counters[:errors]
      @last_counters = @counters.merge(stamp: now)

      average_latency = @http_latency_counter > 0 ?
                        @http_latency_accumulator / @http_latency_counter :
                        0
      @http_latency_accumulator = 0
      @http_latency_counter = 0

      @stats = {
        http_request_rate: http_requests / elapsed,
        error_rate: errors / elapsed,
        average_latency: average_latency,
        agent_count: @agents.size,
        concurrent_requests: @current_request_count
      }
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
  
    def http_request(req)
      @current_request_count += 1
      t0 = Time.now
      @counters[:http_requests] += 1
      return upgrade_request(req) if req.upgrade_protocol
  
      agent = find_agent(req)
      unless agent
        @counters[:errors] += 1
        # puts "Couldn't find agent for #{req.headers}"
        return req.respond(nil, ':status' => 503)
      end

      inject_request_headers(req)
      agent.http_request(req)
      latency = Time.now - t0
      @http_latency_accumulator += latency
      @http_latency_counter += 1
    rescue IOError, SystemCallError
      @counters[:errors] += 1
    rescue => e
      @counters[:errors] += 1
      req.respond(e.inspect, ':status' => 500)
    ensure
      @current_request_count -= 1
    end

    def inject_request_headers(req)
      req.headers['X-Request-ID'] = SecureRandom.uuid
      conn = req.adapter.conn
      req.headers['X-Forwarded-For'] = conn.peeraddr(false)[2]
      req.headers['X-Forwarded-Proto'] = conn.is_a?(OpenSSL::SSL::SSLSocket) ? 'https' : 'http'
    end
  
    def upgrade_request(req)
      case (protocol = req.upgrade_protocol)
      when 'df'
        df_upgrade(req)
      else
        agent = find_agent(req)
        unless agent
          @counters[:errors] += 1
          return req.respond(nil, ':status' => 503)
        end

        agent.http_upgrade(req, protocol)
      end
    end
  
    def df_upgrade(req)
      return req.respond(nil, ':status' => 403) if req.headers['DF-Token'] != @token

      req.adapter.conn << Protocol.df_upgrade_response
      AgentProxy.new(self, req)
    end
  
    def mount(route, agent)
      if route[:path]
        route[:path_regexp] = path_regexp(route[:path])
      end
      @agents[agent] = route
      @routing_changed = true
    end
  
    def unmount(agent)
      @agents.delete(agent)
      @routing_changed = true
    end

    INVALID_HOST = 'INVALID_HOST'

    def find_agent(req)
      compile_agent_routes if @routing_changed

      host = req.headers['Host'] || INVALID_HOST
      path = req.headers[':path']
      default_agent = nil

      @routes.each do |agent, route|
        if route.nil?
          default_agent = agent
          next
        end

        return agent if host == route[:host]
        return agent if path =~ route[:path_regexp]
      end

      return default_agent
    end

    def compile_agent_routes
      @routing_changed = false

      @routes.clear
      @agents.keys.reverse.each do |agent|
        @routes[agent] = @agents[agent]
      end
    end

    def path_regexp(path)
      /^#{path}/
    end
  end
end

# frozen_string_literal: true

require_relative './protocol'
require_relative './agent_proxy'

module Tipi::DigitalFabric
  class Service
    def initialize
      @agents = {}
      recompile_agent_routes
    end
  
    # request routing
  
    def http_request(req)
      return upgrade_request(req) if req.upgrade_protocol
  
      agent = find_agent(req)
      return req.respond(nil, ':status' => 503) unless agent

      agent.http_request(req)
    end
  
    def upgrade_request(req)
      case (protocol = req.upgrade_protocol)
      when 'df'
        df_upgrade(req)
      else
        agent = find_agent(req)
        return req.respond(nil, ':status' => 503) unless agent

        agent.http_upgrade(req, protocol)
      end
    end
  
    def df_upgrade(req)
      req.adapter.conn << Protocol.df_upgrade_response
      AgentProxy.new(self, req)
    end
  
    def mount(route, agent)
      @agents[agent] = route
      @routing_changed = true
    end
  
    def unmount(agent)
      @agents.delete(agent)
      @routing_changed = true
    end

    def recompile_agent_routes
      @routing_changed = false
      default_agent_idx = nil
      @agent_array = []
      @statements = []
      idx = 0
      @agents.each do |agent, route|
        @agent_array << agent
        if route
          @statements << "return @agent_array[#{idx}] if #{route_predicate(route)}; "
        else
          default_agent_idx = idx
        end
        idx += 1
      end
      if default_agent_idx
        @statements.unshift "return @agent_array[#{default_agent_idx}]"
      end
      body = "recompile_routing if @routing_changed; #{@statements.reverse.join}"
      singleton_class.class_eval("def find_agent(req); #{body}; end")
    end

    def route_predicate(route)
      return "(req.headers['Host'] == #{route[:host].inspect})" if route[:host]
      return "(req.headers[':path'] =~ #{path_regexp(route[:path]).inspect})" if route[:path]
      return "true" if route[:catch_all]

      "false"
    end

    def path_regexp(path)
      /^#{path}/
    end
  end
end

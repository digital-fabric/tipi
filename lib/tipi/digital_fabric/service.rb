# frozen_string_literal: true

require_relative './protocol'
require_relative './agent_proxy'

module Tipi::DigitalFabric
  class Service
    def initialize
      @agents = {}
      @routes = {}
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

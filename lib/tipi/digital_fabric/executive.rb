# frozen_string_literal: true

class Tipi::DigitalFabric
  # agent for managing DF service
  class Executive
    def initialize(df_service, route = { path: '/executive' })
      @df_service = df_service
      @df_service.mount(route, self)

      @root_path = route[:path] || '/'
      @relative_path_regexp = /^#{@root_path}\/(.*)/
    end

    def request_relative_path(req)
      path = req.path
      if path =~ @relative_path_regexp
        Regexp.last_match(1)
      else
        raise "Invalid parth #{path}"
      end
    end

    def http_request(req)
      path = request_relative_path(req)
      #{}
    end
  end
# frozen_string_literal: true

require 'tipi'

module Kernel
  def run(app = nil, &block)
    Tipi.app = app || block
  end
end

module Tipi
  class << self
    attr_writer :app

    def app
      return @app if @app
      
      raise 'No app define. The app to run should be set using `Tipi.app = ...`'
    end

    def run_sites(site_map)
      sites = site_map.each_with_object({}) { |(k, v), h| h[k] = v.to_proc }
      valid_hosts = sites.keys

      @app = ->(req) {
        handler = sites[req.host]
        if handler
          handler.call(req)
        else
          req.respond(nil, ':status' => Qeweney::Status::NOT_FOUND)
        end
      }

      @app.define_singleton_method(:valid_hosts) { valid_hosts }
    end
  end
end

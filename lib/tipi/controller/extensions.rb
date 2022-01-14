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
  end
end

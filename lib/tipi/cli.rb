# frozen_string_literal: true

require 'tipi'
require 'fileutils'

module Tipi
  module CLI
    BANNER = "
         ooo
       oo
     o
   \\|/
   / \\   Tipi - A better web server for a better world
  /___\\
"

    def self.start
      display_banner
      require File.expand_path(ARGV[0] || 'app.rb', FileUtils.pwd)
    end

    def self.display_banner
      puts BANNER
      puts
    end
  end
end

__END__

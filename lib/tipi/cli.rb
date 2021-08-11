# frozen_string_literal: true

require 'tipi'

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

    def self.start(dir)
      display_banner
      # require File.expand_path(ARGV[0] || 'app.rb', dir)
    end

    def self.display_banner
      puts BANNER
    end
  end
end

__END__

# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

require_relative '../../security/http1'

$CFLAGS << " -Wno-format-security"
CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/
HTTP1_LIMITS.each { |k, v| $defs << "-D#{k}=#{v}" }

dir_config 'tipi_ext'
create_makefile 'tipi_ext'

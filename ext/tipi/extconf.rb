# frozen_string_literal: true

require 'rubygems'
require 'mkmf'

$CFLAGS << " -Wno-pointer-arith"

CONFIG['optflags'] << ' -fno-strict-aliasing' unless RUBY_PLATFORM =~ /mswin/


dir_config 'tipi_ext'
create_makefile 'tipi_ext'

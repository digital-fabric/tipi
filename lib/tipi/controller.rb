# frozen_string_literal: true

require 'bundler/setup'
require 'json'

# get opts from STDIN
opts = JSON.parse(ARGV[0]) rescue nil

mod_path = "./controller/#{opts['app_type']}_#{opts['mode']}"
require_relative mod_path

controller = Tipi::Controller.new(opts)
trap('SIGTERM') { controller.stop }
controller.run

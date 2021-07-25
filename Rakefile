# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/clean"

require "rake/extensiontask"
Rake::ExtensionTask.new("tipi_ext") do |ext|
  ext.ext_dir = "ext/tipi"
end

task :recompile => [:clean, :compile]
task :default => [:compile, :test]

task :test do
  exec 'ruby test/run.rb'
end

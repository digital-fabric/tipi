# frozen_string_literal: true

require 'bundler/setup'
require 'polyphony'
require 'json'

require 'fileutils'
FileUtils.cd(__dir__)

require_relative 'agent'

class AgentManager
  def initialize
    @running_agents = {}
    @pending_actions = Queue.new
    @processor = spin_loop { process_pending_action }
  end

  def process_pending_action
    action = @pending_actions.shift
    case action[:kind]
    when :start
      start_agent(action[:spec])
    when :stop
      stop_agent(action[:spec])
    end
    sleep 0.05
  end

  def start_agent(spec)
    return if @running_agents[spec]

    @running_agents[spec] = spin do
      while true
        launch_agent_from_spec(spec)
        sleep 1
      end
    ensure
      @running_agents.delete(spec)
    end
  end

  def stop_agent(spec)
    fiber = @running_agents[spec]
    return unless fiber

    fiber.terminate
    fiber.await
  end

  def update
    return unless @pending_actions.empty?

    current_specs = @running_agents.keys
    updated_specs = agent_specs

    to_start = updated_specs - current_specs
    to_stop = current_specs - current_specs

    to_start.each { |s| @pending_actions << { kind: :start, spec: s } }
    to_stop.each { |s| @pending_actions << { kind: :stop, spec: s } }
  end

  def run
    every(2) { update }
  end
end

class RealityAgentManager < AgentManager
  def agent_specs
    (1..400).map { |i| { id: i } }
  end

  def launch_agent_from_spec(spec)
    # Polyphony::Process.watch("ruby agent.rb #{spec[:id]}")
    Polyphony::Process.watch do
      spin_loop(interval: 60) { GC.start }
      agent = SampleAgent.new(spec[:id], '/tmp/df.sock')
      puts "Starting agent #{spec[:id]} pid: #{Process.pid}"
      agent.run
    end
  end
end

puts "Agent manager pid: #{Process.pid}"

manager = RealityAgentManager.new
manager.run

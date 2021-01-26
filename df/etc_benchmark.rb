# frozen_string_literal: true

require 'securerandom'

def generate
  SecureRandom.uuid
end

count = 100000

GC.disable
t0 = Time.now
count.times { generate }
elapsed = Time.now - t0
puts "rate: #{count / elapsed}/s"
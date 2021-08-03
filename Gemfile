source 'https://rubygems.org'

gemspec
%w{polyphony qeweney}.each do |dep|
  dir = "../#{dep}"
  gem(dep, path: dir) if File.directory?(dir)
end
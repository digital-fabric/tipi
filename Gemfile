source 'https://rubygems.org'

gemspec

# for local development
%w{polyphony ever qeweney h1p}.each do |dep|
  dir = "../#{dep}"
  gem(dep, path: dir) if File.directory?(dir)
end

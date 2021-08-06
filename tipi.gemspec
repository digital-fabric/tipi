require_relative './lib/tipi/version'

Gem::Specification.new do |s|
  s.name        = 'tipi'
  s.version     = Tipi::VERSION
  s.licenses    = ['MIT']
  s.summary     = 'Tipi - the All-in-one Web Server for Ruby Apps'
  s.author      = 'Sharon Rosner'
  s.email       = 'sharon@noteflakes.com'
  s.files       = `git ls-files`.split
  s.homepage    = 'http://github.com/digital-fabric/tipi'
  s.metadata    = {
    "source_code_uri" => "https://github.com/digital-fabric/tipi"
  }
  s.rdoc_options = ["--title", "tipi", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.extensions = ["ext/tipi/extconf.rb"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 2.6'

  s.executables   = ['tipi']

  s.add_runtime_dependency      'polyphony',          '~>0.67'
  s.add_runtime_dependency      'qeweney',            '~>0.13.1'
  
  s.add_runtime_dependency      'http-2',             '~>0.11'
  s.add_runtime_dependency      'rack',               '>=2.0.8', '<2.3.0'
  s.add_runtime_dependency      'websocket',          '~>1.2.8'
  s.add_runtime_dependency      'acme-client',        '~>2.0.8'

  # for digital fabric
  s.add_runtime_dependency      'msgpack',            '~>1.4.2'

  s.add_development_dependency  'rake-compiler',        '1.1.1'
  s.add_development_dependency  'rake',               '~>12.3.3'
  s.add_development_dependency  'localhost',          '~>1.1.4'
  s.add_development_dependency  'minitest',           '~>5.11.3'
  s.add_development_dependency  'minitest-reporters', '~>1.4.2'
  s.add_development_dependency  'simplecov',          '~>0.17.1'

  s.add_development_dependency  'cuba',               '~>3.9.3'
end

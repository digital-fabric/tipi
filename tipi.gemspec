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
    "source_code_uri" => "https://github.com/digital-fabric/tipi",
    "documentation_uri" => "https://www.rubydoc.info/gems/tipi",
    "homepage_uri" => "https://github.com/digital-fabric/tipi",
    "changelog_uri" => "https://github.com/digital-fabric/tipi/blob/master/CHANGELOG.md"
  }
  s.rdoc_options = ["--title", "tipi", "--main", "README.md"]
  s.extra_rdoc_files = ["README.md"]
  s.require_paths = ["lib"]
  s.required_ruby_version = '>= 3.2'

  s.executables   = ['tipi']

  s.add_runtime_dependency      'base64',             '~>0.3'
  s.add_runtime_dependency      'mutex_m',            '~>0.3'

  s.add_runtime_dependency      'polyphony',          '~>1.4'
  s.add_runtime_dependency      'ever',               '~>0.2'
  s.add_runtime_dependency      'qeweney',            '~>0.24'
  s.add_runtime_dependency      'extralite',          '~>2.13'
  s.add_runtime_dependency      'h1p',                '~>1.1'

  s.add_runtime_dependency      'http-2',             '~>1.1'
  s.add_runtime_dependency      'rack',               '>=2.0.8', '<3.3.0'
  s.add_runtime_dependency      'websocket',          '~>1.2.11'
  s.add_runtime_dependency      'acme-client',        '~>2.0.26'
  s.add_runtime_dependency      'localhost',          '~>1.6.0'

  # for digital fabric
  s.add_runtime_dependency      'msgpack',            '~>1.8.0'

  s.add_development_dependency  'logger',             '~>1.7'
  s.add_development_dependency  'ostruct',            '~>0.3'

  s.add_development_dependency  'rake',               '~>13.0.6'
  s.add_development_dependency  'minitest',           '~>5.18.1'
  s.add_development_dependency  'simplecov',          '~>0.22.0'
  s.add_development_dependency  'memory_profiler',    '~>1.0.1'

  s.add_development_dependency  'cuba',               '~>3.9.3'
end

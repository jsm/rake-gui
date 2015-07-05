Gem::Specification.new do |s|
  s.name        = 'rake-gui'
  s.version     = '0.1.0'
  s.date        = '2015-06-30'
  s.summary     = "Run a rake command through a GUI"
  s.description = "Run a rake command through a GUI"
  s.authors     = ["Jon San Miguel"]
  s.email       = 'j.sm@berkeley.edu'
  s.files       = Dir["lib/**/*"] + Dir["bin/**/*"]
  s.homepage    = 'http://rubygems.org/gems/rake-gui'
  s.license     = 'MIT'

  # Runtime Dependencies
  s.add_runtime_dependency 'activesupport', '~> 4.1.0'
  s.add_runtime_dependency 'colorize', '~> 0.7.0'
  s.add_runtime_dependency 'haml', '~> 4.0.0'
  s.add_runtime_dependency 'sinatra', '~> 1.4.0'

  # Development Dependencies
  s.add_development_dependency 'rake', '~> 10.4.0'

  s.executables << 'rakeg'
end

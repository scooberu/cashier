Gem::Specification.new do |s|
  s.name        = 'cashier'
  s.version     = '0.1.0'
  s.date        = '2022-09-22'
  s.summary     = 'Simple command-line budgeting tool'
  s.description = 'A quick command-line interface designed to manage outstanding debts--and figure out which ones to pay off first.'
  s.authors     = ['Scott Beru']
  s.email       = 'scott@beru.dev'
  s.license     = "Beerware"
  s.files       = Dir['lib/*.rb']
  s.add_dependency 'awesome_print', '1.9.2'
  s.add_dependency 'colorize', '0.8.1'
  s.add_dependency 'tty-prompt', '0.23.1'
end

# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name          = 'csv_migration'
  s.version       = '0.0.3'
  s.date          = '2021-01-20'
  s.summary       = 'Migration system from a csv file'
  s.description   = 'You can make parsing CSV file, generate from it hash data and then save to DB'
  s.authors       = ['Danilevsky Kirill']
  s.email         = 'k.danilevsky@gmail.com'
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.require_paths = ['lib']
  s.files         = %w[lib/csv_migration.rb]
  s.required_ruby_version = '>= 2.5.0'
  s.homepage      = 'https://github.com/kirill-dan/csv_migration'
  s.license       = 'MIT'
  s.add_development_dependency 'minitest', '~> 5.13.0'
end

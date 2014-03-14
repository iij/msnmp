MRuby::Gem::Specification.new('mruby-msnmp') do |spec|
  spec.license = 'MIT'
  spec.authors = 'Internet Initiative Japan'
  
  spec.add_dependency 'mruby-string-ext'
  spec.add_dependency 'mruby-io'
  spec.add_dependency 'mruby-socket'
end

# -*- encoding: utf-8 -*-
Gem::Specification.new do |s|
  s.name = "msnmp"
  s.version = "0.0.1"
  s.authors = ["maebashi"]
  s.homepage = ""
  s.summary = %q{msnmp}
  s.description = %q{msnmp}
  s.files         = `git ls-files`.split("\n").select {|e| /^tmp/!~e}
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f
) }
  s.require_paths = ["lib"]
end

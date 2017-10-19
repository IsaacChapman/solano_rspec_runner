# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "solano_rspec_runner/version"

Gem::Specification.new do |spec|
  spec.name          = "solano_rspec_runner"
  spec.version       = SolanoRspecRunner::VERSION
  spec.authors       = ["Isaac Chapman"]
  spec.email         = ["isaac@solanolabs.com"]

  spec.summary       = "Run RSpec on Solano CI with corrected Junit output"
  #spec.description   = "TODO: create longer description"
  spec.homepage      = "https://ci.solanolabs.com/"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec_junit_formatter"
  spec.add_dependency "nokogiri" 
  spec.add_dependency "rake"
  spec.add_dependency "rspec"
end

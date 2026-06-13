# frozen_string_literal: true

require_relative "lib/tans_parser/version"

Gem::Specification.new do |spec|
  spec.name          = "tans-parser"
  spec.version       = TansParser::VERSION
  spec.authors       = ["Haluk Durmus"]
  spec.email         = ["haluk_durmus@yahoo.de"]

  spec.summary       = "Parse ANSI terminal output into structured data with UI element recognition"
  spec.description   = "tans-parser parses raw terminal output with ANSI escape sequences " \
                       "into a structured grid representation with per-cell attributes " \
                       "(char, fg, bg, bold, italic, underline, blink). " \
                       "Includes a query API (State) for text search, color inspection, " \
                       "and JSON output, plus heuristic UI element recognition (Selector) " \
                       "for buttons, checkboxes, dialogs, statusbars, and progress bars."
  spec.homepage      = "https://github.com/vurte/tans-parser"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "LICENSE.txt",
    "CHANGELOG.md",
  ]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "reek", "~> 6.3"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-rake", "~> 0.7"
  spec.add_development_dependency "rubocop-rspec", "~> 3.6"
  spec.add_development_dependency "simplecov", "~> 0.22"

  spec.add_development_dependency "benchmark-ips", "~> 2.13"

  spec.add_dependency "unicode-display_width", "~> 2.5"
end

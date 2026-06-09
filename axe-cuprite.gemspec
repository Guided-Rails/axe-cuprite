# frozen_string_literal: true

require_relative "lib/axe/cuprite/version"

Gem::Specification.new do |spec|
  spec.name        = "axe-cuprite"
  spec.version     = AxeCuprite::VERSION
  spec.authors     = ["Abdullah Hashim"]
  spec.email       = ["abdullah@guidedrails.com"]

  spec.summary     = "Run axe-core accessibility tests in Capybara + Cuprite (CDP), no Selenium."
  spec.description = <<~DESC
    axe-cuprite runs the axe-core accessibility engine against pages rendered in
    Capybara system/feature tests and exposes the results as RSpec matchers
    (be_axe_clean / be_accessible). Unlike Deque's official axe-core-capybara gem,
    it never touches Selenium-specific driver internals: axe is driven entirely
    through Capybara's driver-neutral JavaScript API, so it works with Cuprite
    and any other real-browser driver.
  DESC

  spec.homepage = "https://github.com/Guided-Rails/axe-cuprite"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["source_code_uri"]   = spec.homepage
  spec.metadata["changelog_uri"]     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/axe/cuprite/vendor/axe.min.js",
    "lib/axe/cuprite/vendor/axe-core-LICENSE.txt",
    "lib/axe/cuprite/tasks/*.rake",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  # Runtime: only Capybara. We drive axe purely through Capybara's
  # driver-neutral JS API, so we deliberately do NOT depend on cuprite,
  # ferrum, selenium or rspec — consumers bring their own driver/framework.
  spec.add_dependency "capybara", ">= 3.0", "< 4.0"

  # Development / test only: this is how WE prove it works on Cuprite.
  spec.add_development_dependency "cuprite", "~> 0.17"
  spec.add_development_dependency "ferrum", "~> 0.17"
  spec.add_development_dependency "puma", ">= 5.0", "< 9.0"
  spec.add_development_dependency "rack", ">= 2.0", "< 4.0"
  spec.add_development_dependency "rackup", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.86"
  spec.add_development_dependency "rubocop-rake", "~> 0.7"
  spec.add_development_dependency "rubocop-rspec", "~> 3.0"
end

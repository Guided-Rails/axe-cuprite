# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are declared in axe-cuprite.gemspec
gemspec

# Development / test only: this is how WE prove it works on Cuprite. Kept out
# of the gemspec so consumers bring their own driver/framework.
group :development, :test do
  gem "cuprite", "~> 0.17"
  gem "ferrum", "~> 0.17"
  gem "puma", ">= 5.0", "< 9.0"
  gem "rack", ">= 2.0", "< 4.0"
  gem "rackup", "~> 2.0"
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rubocop", "~> 1.86"
  gem "rubocop-rake", "~> 0.7"
  gem "rubocop-rspec", "~> 3.0"
end

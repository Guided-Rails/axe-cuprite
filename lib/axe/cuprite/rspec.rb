# frozen_string_literal: true

require "axe/cuprite"
require "axe/cuprite/rspec/matchers"

module AxeCuprite
  module RSpec
    # Methods mixed into RSpec example groups to expose the matchers.
    module DSL
      # expect(page).to be_axe_clean ...
      def be_axe_clean
        AxeCuprite::RSpec::BeAxeClean.new
      end

      # Alias: expect(page).to be_accessible ...
      def be_accessible
        AxeCuprite::RSpec::BeAxeClean.new
      end
    end
  end
end

if defined?(::RSpec) && ::RSpec.respond_to?(:configure)
  ::RSpec.configure do |config|
    config.include AxeCuprite::RSpec::DSL
  end
end

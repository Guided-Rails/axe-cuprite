# frozen_string_literal: true

require "spec_helper"
require "rake"

# Load the AxeCupriteVendor helper module defined alongside the rake tasks.
# It lives in a .rake file, so we extend the Rake DSL and `load` it (the
# namespace/task definitions are harmless; we only exercise the module).
extend Rake::DSL # rubocop:disable Style/MixinUsage -- top-level DSL needed to `load` the .rake file

load File.expand_path("../lib/axe/cuprite/tasks/axe.rake", __dir__)

RSpec.describe AxeCupriteVendor do
  describe ".update!" do
    context "with a malformed version" do
      # A bad version must abort up front with the guard's message — proving it
      # never reaches the network call or file writes that splice the value
      # into the registry URL and version.rb. "Invalid version" appears only in
      # that guard, so matching it confirms where execution stopped.
      [
        "4.12.0/../some-other-pkg",
        '4.12.0";system("rm -rf /")#',
        "latest",
        "4.12",
        "v4.12.0",
        "",
        "  4.12.0  "
      ].each do |bad|
        it "aborts on #{bad.inspect}" do
          expect { described_class.update!(bad) }
            .to raise_error(SystemExit, /Invalid version/)
        end
      end
    end

    context "with a well-formed version" do
      # The guard must let valid semver through; we stub the first network call
      # so the example proves validation passed without actually vendoring.
      %w[4.12.0 0.0.1 10.20.30 4.12.0-beta.1].each do |good|
        it "accepts #{good.inspect}" do
          allow(described_class).to receive(:registry_dist).and_raise("reached network")
          expect { described_class.update!(good) }.to raise_error("reached network")
        end
      end
    end
  end
end

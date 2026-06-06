# frozen_string_literal: true

require "bundler/gem_tasks"

require_relative "lib/axe/cuprite/version"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  # rspec not available (e.g. in a production install) — skip the spec task.
end

# Load the vendoring tasks (rake axe:update / axe:version).
load File.expand_path("lib/axe/cuprite/tasks/axe.rake", __dir__)

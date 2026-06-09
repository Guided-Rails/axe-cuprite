# frozen_string_literal: true

require "bundler/gem_tasks"

require_relative "lib/axe/cuprite/version"

default_tasks = []

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  default_tasks << :spec
rescue LoadError
  # rspec not available (e.g. in a production install) — skip the spec task.
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  default_tasks << :rubocop
rescue LoadError
  # rubocop not available (e.g. in a production install) — skip the lint task.
end

task default: default_tasks

# Load the vendoring tasks (rake axe:update / axe:version).
load File.expand_path("lib/axe/cuprite/tasks/axe.rake", __dir__)

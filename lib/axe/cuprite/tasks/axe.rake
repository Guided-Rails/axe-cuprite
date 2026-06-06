# frozen_string_literal: true

require "open-uri"
require "fileutils"
require "json"

namespace :axe do
  desc "Refresh the vendored axe-core engine. Usage: rake 'axe:update[4.12.0]' or VERSION=4.12.0 rake axe:update (default: latest)"
  task :update, [:version] do |_task, args|
    version = args[:version] || ENV["VERSION"] || AxeCupriteVendor.latest_version
    AxeCupriteVendor.update!(version)
  end

  desc "Print the currently vendored axe-core version"
  task :version do
    puts AxeCupriteVendor.vendored_version
  end
end

# Helpers for vendoring axe-core. Kept in a module so the rake tasks stay thin
# and the logic is easy to read. Never used at runtime — vendoring is a
# development-time step; the engine ships in the gem.
module AxeCupriteVendor
  VENDOR_DIR   = File.expand_path("../vendor", __dir__)
  AXE_JS       = File.join(VENDOR_DIR, "axe.min.js")
  AXE_LICENSE  = File.join(VENDOR_DIR, "axe-core-LICENSE.txt")
  VERSION_FILE = File.expand_path("../version.rb", __dir__)
  REGISTRY     = "https://registry.npmjs.org/axe-core"
  CDN          = "https://unpkg.com/axe-core"

  module_function

  def update!(version)
    FileUtils.mkdir_p(VENDOR_DIR)

    puts "Fetching axe-core@#{version} ..."
    js = download("#{CDN}@#{version}/axe.min.js")
    unless js =~ /axe v#{Regexp.escape(version)}\b/
      warn "Warning: downloaded axe.min.js banner does not mention v#{version} — continuing anyway."
    end
    license = download("#{CDN}@#{version}/LICENSE")

    File.write(AXE_JS, js)
    File.write(AXE_LICENSE, license)
    bump_version_constant(version)

    puts "Vendored axe-core #{version}:"
    puts "  #{AXE_JS} (#{js.bytesize} bytes)"
    puts "  #{AXE_LICENSE}"
    puts "  updated AXE_CORE_VERSION in #{VERSION_FILE}"
    puts "Remember to note the version bump in CHANGELOG.md."
  end

  def latest_version
    JSON.parse(download("#{REGISTRY}/latest")).fetch("version")
  end

  def vendored_version
    File.read(AXE_JS)[/axe v([0-9][0-9.]*)/, 1] || "unknown"
  end

  def download(url)
    URI.parse(url).open(&:read)
  rescue OpenURI::HTTPError => e
    abort "Failed to download #{url}: #{e.message}"
  end

  def bump_version_constant(version)
    contents = File.read(VERSION_FILE)
    updated = contents.sub(/(AXE_CORE_VERSION\s*=\s*)"[^"]*"/, %(\\1"#{version}"))
    File.write(VERSION_FILE, updated)
  end
end

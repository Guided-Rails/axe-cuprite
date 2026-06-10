# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open-uri"
require "rubygems/package"
require "stringio"
require "zlib"

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

  desc "Verify the vendored axe.min.js against its recorded sha512 checksum"
  task :verify do
    AxeCupriteVendor.verify_vendored!
  end
end

# Helpers for vendoring axe-core. Kept in a module so the rake tasks stay thin
# and the logic is easy to read. Never used at runtime — vendoring is a
# development-time step; the engine ships in the gem.
#
# Supply-chain note: the vendored axe.min.js is the JavaScript this gem injects
# into every consumer's browser session, so its integrity is the gem's most
# important supply-chain property. We therefore download the *official npm
# tarball* from registry.npmjs.org (not a CDN re-serving it), verify it against
# the sha512 integrity the registry publishes in its metadata, and abort on any
# mismatch before a single byte is written. The verified content hash of the
# extracted axe.min.js is recorded next to it (axe.min.js.sha512) so reviewers
# and CI can re-check the vendored artifact without re-downloading.
module AxeCupriteVendor
  VENDOR_DIR   = File.expand_path("../vendor", __dir__)
  AXE_JS       = File.join(VENDOR_DIR, "axe.min.js")
  AXE_SHA512   = File.join(VENDOR_DIR, "axe.min.js.sha512")
  AXE_LICENSE  = File.join(VENDOR_DIR, "axe-core-LICENSE.txt")
  VERSION_FILE = File.expand_path("../version.rb", __dir__)
  REGISTRY     = "https://registry.npmjs.org/axe-core"

  module_function

  # A semver-ish version string: three dot-separated numbers with an optional
  # prerelease suffix. Rejecting anything else keeps the value safe to splice
  # into the registry URL and into version.rb, and catches honest typos before
  # they corrupt the vendor directory.
  VERSION_FORMAT = /\A\d+\.\d+\.\d+(-[\w.]+)?\z/

  def update!(version)
    abort "Invalid version: #{version.inspect}" unless version.match?(VERSION_FORMAT)

    FileUtils.mkdir_p(VENDOR_DIR)

    dist = registry_dist(version)
    puts "Downloading #{dist.fetch("tarball")} ..."
    tarball = download(dist.fetch("tarball"))
    verify_tarball!(tarball, dist)

    js, license = extract(tarball, "package/axe.min.js", "package/LICENSE")
    verify_banner!(js, version)

    File.write(AXE_JS, js)
    File.write(AXE_LICENSE, license)
    File.write(AXE_SHA512, "#{Digest::SHA512.hexdigest(js)}  axe.min.js\n")
    bump_version_constant(version)

    report(version, js)
  end

  def latest_version
    JSON.parse(download("#{REGISTRY}/latest")).fetch("version")
  end

  def vendored_version
    File.read(AXE_JS)[/axe v([0-9][0-9.]*)/, 1] || "unknown"
  end

  def verify_vendored!
    abort "No recorded checksum at #{AXE_SHA512} — run rake axe:update first." unless File.exist?(AXE_SHA512)

    expected = File.read(AXE_SHA512).split.first
    actual   = Digest::SHA512.hexdigest(File.binread(AXE_JS))
    unless actual == expected
      abort <<~MSG
        MISMATCH: #{AXE_JS} does not match its recorded sha512.
          recorded: #{expected}
          actual:   #{actual}
      MSG
    end

    puts "OK: axe.min.js matches its recorded sha512."
  end

  def registry_dist(version)
    puts "Fetching axe-core@#{version} metadata from #{REGISTRY} ..."
    JSON.parse(download("#{REGISTRY}/#{version}")).fetch("dist")
  end

  # Abort unless the downloaded tarball matches the integrity values the npm
  # registry publishes for it (dist.integrity sha512, plus legacy dist.shasum).
  def verify_tarball!(tarball, dist)
    integrity = dist["integrity"]
    abort "Registry metadata has no sha512 integrity for the tarball — refusing to vendor." unless integrity&.start_with?("sha512-")

    actual = "sha512-#{Digest::SHA512.base64digest(tarball)}"
    unless actual == integrity
      abort <<~MSG
        Tarball integrity check FAILED — refusing to vendor.
          expected (registry dist.integrity): #{integrity}
          actual   (downloaded tarball):      #{actual}
      MSG
    end

    shasum = dist["shasum"]
    if shasum && Digest::SHA1.hexdigest(tarball) != shasum
      abort "Tarball sha1 shasum mismatch (registry says #{shasum}) — refusing to vendor."
    end

    puts "  tarball integrity verified (#{integrity})"
  end

  # Secondary sanity check on the extracted engine itself; fatal on mismatch.
  def verify_banner!(engine_js, version)
    return if engine_js.match?(/axe v#{Regexp.escape(version)}\b/)

    abort "Extracted axe.min.js banner does not mention v#{version} — refusing to vendor."
  end

  def extract(tarball, *paths)
    found = {}
    Zlib::GzipReader.wrap(StringIO.new(tarball)) do |gz|
      Gem::Package::TarReader.new(gz) do |tar|
        tar.each { |entry| found[entry.full_name] = entry.read if paths.include?(entry.full_name) }
      end
    end
    missing = paths - found.keys
    abort "Tarball is missing expected file(s): #{missing.join(", ")}" unless missing.empty?
    found.values_at(*paths)
  end

  def download(url)
    URI.parse(url).open("rb", &:read)
  rescue OpenURI::HTTPError => e
    abort "Failed to download #{url}: #{e.message}"
  end

  def bump_version_constant(version)
    contents = File.read(VERSION_FILE)
    updated = contents.sub(/(AXE_CORE_VERSION\s*=\s*)"[^"]*"/, %(\\1"#{version}"))
    File.write(VERSION_FILE, updated)
  end

  def report(version, engine_js)
    puts "Vendored axe-core #{version} (tarball integrity verified):"
    puts "  #{AXE_JS} (#{engine_js.bytesize} bytes)"
    puts "  #{AXE_SHA512}"
    puts "  #{AXE_LICENSE}"
    puts "  updated AXE_CORE_VERSION in #{VERSION_FILE}"
    puts "Remember to note the version bump in CHANGELOG.md."
  end
end

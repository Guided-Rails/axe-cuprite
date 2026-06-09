# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- `rake axe:update` now vendors axe-core from the official npm registry tarball
  (`registry.npmjs.org`) instead of the unpkg CDN, verifies the tarball against
  the registry-published sha512 `dist.integrity` (and legacy `dist.shasum`)
  **before writing anything**, and treats a banner/version mismatch as fatal
  instead of a warning ([#11](https://github.com/Guided-Rails/axe-cuprite/issues/11)).
- The sha512 of the vendored `axe.min.js` is now recorded in
  `lib/axe/cuprite/vendor/axe.min.js.sha512`; a new `rake axe:verify` task
  re-checks the vendored engine against it, and CI runs it on every build.

## [0.1.1] - 2026-06-09

### Added
- GitHub Actions CI (`.github/workflows/ci.yml`): runs the RSpec suite under
  Cuprite/headless Chrome across Ruby 3.0–3.4 and a RuboCop lint job, on every
  push to `main` and all pull requests.

### Fixed
- `Injector#inject_source!` no longer appends a second `<script>` tag when a hard
  injection failure occurs. The retry flow is now a single linear path
  (`execute_script` → check → `add_script_tag` fallback → check → raise), so the
  fallback runs at most once.

## [0.1.0] - 2026-06-06

### Added
- Initial release of **axe-cuprite**.
- Vendored **axe-core 4.12.0** (`lib/axe/cuprite/vendor/axe.min.js`, MPL-2.0).
- `AxeCuprite::Runner` — framework-agnostic runner that injects axe and runs it
  through Capybara's driver-neutral JavaScript API (works on Cuprite/Ferrum with
  **zero Selenium dependency**), with a configurable timeout decoupled from
  `Capybara.default_max_wait_time`.
- Typed result objects: `Results`, `Violation`, `Node`, `ContrastData`.
- RSpec matcher `be_axe_clean` (alias `be_accessible`) with chainable DSL:
  `.within`, `.excluding`, `.checking_only`, `.skipping`, `.according_to`,
  `.with_options`, `.with_timeout`. Actionable, grouped failure messages that
  surface fg/bg color and contrast ratio for color-contrast violations.
- `AxeCuprite.configure` for timeout, default options/tags, global skip-list,
  auto-inject toggle, and report-only mode.
- `rake axe:update[VERSION]` to refresh the vendored axe-core engine and bump
  the `AXE_CORE_VERSION` constant.

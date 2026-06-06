# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

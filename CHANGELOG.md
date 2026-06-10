# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `config.include_html` (default `true`) — set to `false` to suppress the
  truncated outer-HTML snippets that failure messages and `report_only` logs
  print for each offending element. Useful for suites that render sensitive data
  (staging-backed tests, seeded PII), keeping page content out of CI logs while
  still reporting rule id, selector, and check message. Documented the snippet
  behavior and `logger` guidance in the README
  ([#14](https://github.com/Guided-Rails/axe-cuprite/issues/14)).

### Fixed
- The result wrappers (`Results`/`Violation`/`Node`/`ContrastData`) now honor
  their documented read-only contract: `@raw` is deep-frozen at construction, so
  `raw` and `to_h` can safely expose the live underlying hash without a caller
  being able to mutate the wrapper's internal state (which, via memoization,
  could previously desync `violations`/`incomplete` from `raw`)
  ([#17](https://github.com/Guided-Rails/axe-cuprite/issues/17)).
- `Injector#inject_source!` no longer hides the real cause of an injection
  failure behind a blanket Content-Security-Policy message. When both the
  primary `execute_script` path and the `add_script_tag` fallback fail, the
  exceptions they raised are now captured and appended to the `InjectionError`
  message (`Underlying errors: execute_script: ...; add_script_tag: ...`), so a
  dead browser, dead CDP session, or misconfigured driver is no longer
  misattributed to CSP ([#15](https://github.com/Guided-Rails/axe-cuprite/issues/15)).
- `Injector#timeout_error?` no longer reclassifies arbitrary failures as
  `AxeCuprite::TimeoutError` just because the error message mentions a timeout.
  A genuine page-side JavaScript error (e.g. a `Ferrum::JavaScriptError` from axe
  or the app whose text happens to contain "timeout") now propagates untouched
  instead of being rewritten with misleading "increase the timeout / scope the
  run" guidance. Classification is driven by error class (Ferrum's
  timeout/script-timeout classes), with a narrow class-gated message check only
  for Ferrum's async-evaluation "timed out promise" case; this also removes a
  dead code branch that could never affect the result
  ([#16](https://github.com/Guided-Rails/axe-cuprite/issues/16)).

### Security
- `rake axe:update` now vendors axe-core from the official npm registry tarball
  (`registry.npmjs.org`) instead of the unpkg CDN, verifies the tarball against
  the registry-published sha512 `dist.integrity` (and legacy `dist.shasum`)
  **before writing anything**, and treats a banner/version mismatch as fatal
  instead of a warning ([#11](https://github.com/Guided-Rails/axe-cuprite/issues/11)).
- The sha512 of the vendored `axe.min.js` is now recorded in
  `lib/axe/cuprite/vendor/axe.min.js.sha512`; a new `rake axe:verify` task
  re-checks the vendored engine against it, and CI runs it on every build.
- Hardened the CI workflow: added a least-privilege `permissions: contents: read`
  block (the `GITHUB_TOKEN` previously inherited the repo default, potentially
  write-all) and pinned `actions/checkout` and `ruby/setup-ruby` to full commit
  SHAs instead of mutable major-version tags. Added a Dependabot config
  (`.github/dependabot.yml`) for the `github-actions` and `bundler` ecosystems so
  the pinned SHAs and gem dependencies get automated update PRs
  ([#12](https://github.com/Guided-Rails/axe-cuprite/issues/12)).

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

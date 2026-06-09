# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, and others) when working with code
in this repository. To have Claude Code read it automatically, symlink it locally:
`ln -s AGENTS.md CLAUDE.md` (keep the symlink out of version control — e.g. add `/CLAUDE.md` to
`.git/info/exclude`).

## What this gem is

`axe-cuprite` runs the [axe-core](https://github.com/dequelabs/axe-core) accessibility engine
against pages in Capybara system/feature tests and exposes the results as RSpec matchers
(`be_axe_clean` / `be_accessible`) plus a framework-agnostic `AxeCuprite::Runner`.

The whole reason this gem exists: Deque's official `axe-core-capybara` reaches into the
Capybara driver's **Selenium** `browser` object to inject and run axe, so it breaks on
**Cuprite** (the Ferrum/CDP headless-Chrome driver, which has no Selenium browser). This gem
drives axe exclusively through Capybara's **driver-neutral** JS API (`execute_script`,
`evaluate_async_script`) and Ferrum's public API — **never** Selenium internals. Cuprite is the
primary must-pass target; staying driver-agnostic is a bonus, not the goal.

**The only runtime dependency is Capybara.** Do not add a runtime dependency on cuprite, ferrum,
selenium, or rspec — consumers bring their own driver/framework. cuprite/ferrum/rspec are
**development** dependencies (that's how *we* prove the no-Selenium path works). Any reference to
Ferrum/Cuprite in `lib/` must be reflectively/duck-typed and guarded (see `Injector#ferrum_page`),
never a hard `require`.

## Commands

```sh
bundle install
bundle exec rspec                       # full suite under Cuprite (needs Chrome/Chromium)
bundle exec rspec spec/runner_spec.rb   # one file
bundle exec rspec spec/matcher_spec.rb:42  # single example by line
rake spec                               # same as bundle exec rspec
```

Vendoring the axe-core engine (development-time only — never fetched at runtime):

```sh
rake 'axe:update[4.12.0]'   # pin a version: downloads axe.min.js + LICENSE, bumps AXE_CORE_VERSION
rake axe:update             # grab latest from npm
rake axe:version            # print the currently vendored version
rake axe:verify             # check vendored axe.min.js against its recorded sha512 (CI runs this)
```

`axe:update` is supply-chain hardened: it downloads the official tarball from
registry.npmjs.org (never a CDN), verifies the registry-published sha512 `dist.integrity`
(and `dist.shasum`) **before writing anything**, treats a banner/version mismatch as fatal,
and records the engine's sha512 in `lib/axe/cuprite/vendor/axe.min.js.sha512`. Keep all of
that intact — the vendored file is the JS injected into every consumer's browser session.

After `axe:update`, note the bump in `CHANGELOG.md` by hand (the rake task reminds you but does
not edit the changelog).

## Architecture

Load paths: `require "axe/cuprite"` for the runner only; `require "axe/cuprite/rspec"` (in a
spec_helper) to also mix the matchers into RSpec example groups. `lib/axe-cuprite.rb` is a thin
alias for `lib/axe/cuprite.rb`.

Request flow for an assertion:

```
be_axe_clean (matcher, builds context+options) -> Runner (merges global config) -> Injector (inject + run axe) -> Results/Violation/Node/ContrastData
```

- **`Injector`** (`lib/axe/cuprite/injector.rb`) — the make-or-break class. Read its header
  comment before touching it. Two subtleties it deliberately handles:
  1. **Async callback convention.** Ferrum/Capybara wrap the JS in a Promise and append the
     resolve callback as the *last* entry of `arguments`, so `RUN_JS` resolves via
     `arguments[arguments.length - 1]`.
  2. **Timeout decoupling.** Ferrum wraps the promise in `setTimeout(reject, wait*1000)`, and
     through `evaluate_async_script` that `wait` is `Capybara.default_max_wait_time` (often 2s —
     far too short for `axe.run`). On Cuprite we therefore call Ferrum's
     `page.evaluate_async(script, explicit_wait, *args)` **directly** with our own timeout
     (default 30s). Non-Ferrum drivers fall back to `evaluate_async_script` under a temporarily
     raised wait time. The spec_helper sets `default_max_wait_time = 2` on purpose to keep proving
     this decoupling holds.
- **Injection** is idempotent (guarded on `typeof window.axe === 'undefined'`) so repeated
  assertions on one page don't re-send ~500KB. Primary path is `execute_script` (CDP
  `Runtime.evaluate`, **not** subject to the page CSP); fallback is Ferrum's
  `add_script_tag(content:)`; if both fail to land axe it raises `InjectionError` with a
  CSP-pointed message.
- **Only `violations` and `incomplete`** are carried back across the CDP boundary (`RUN_JS`
  slims the payload) — the full axe results object (`passes`/`inapplicable`) can be huge.
- **`Runner`** (`runner.rb`) merges global config *underneath* caller options (caller wins):
  `default_options` deep-merged, `default_tags` become a `runOnly` tag scope only if nothing
  already scopes `runOnly`, `skip_rules` disable rules without clobbering an explicit caller
  setting.
- **`BeAxeClean`** (`rspec/matchers.rb`) holds the chainable DSL (`within`, `excluding`,
  `checking_only`, `according_to`, `skipping`, `with_options`, `with_timeout`). All chainers
  return `self`. `.checking_only` (rule scope) and `.according_to` (tag scope) are mutually
  exclusive — axe's `runOnly` takes one or the other — and combining them raises `ArgumentError`.
  This class also owns the grouped, color-contrast-aware failure messages.
- **`Normalize`** (`normalize.rb`) lets callers pass friendly symbols (`:color_contrast`,
  `:best_practice`) or axe ids (`"color-contrast"`) interchangeably — it just `tr("_", "-")`.
  Apply it anywhere a rule id or tag enters the system.
- **Results objects** (`results.rb`) are read-only typed wrappers over the raw axe hash:
  `Results -> Violation -> Node -> ContrastData`. `ContrastData` is found by scanning a node's
  `any[]` checks for one whose `data` has `contrastRatio`; it's `nil` for non-contrast rules.
- **`Configuration`** (`configuration.rb`) via `AxeCuprite.configure`. `report_only = true` logs
  violations instead of failing (eases incremental adoption); negated assertions
  (`not_to be_axe_clean`) ignore the flag.

## Tests

The suite boots a tiny Rack app (`spec/support/fixture_app.rb`, no Sinatra) serving static HTML
fixtures over Capybara+Cuprite. Key fixtures and what they prove:

- `/bad_contrast` — the headline case: `#585858` text passes contrast alone (~7.7:1) but
  `opacity:0.5` composites it toward `#ababab` over white, dropping to ~2.3:1 (fails AA). Only
  color-contrast should fail here.
- `/csp` — a strict `script-src 'self'` page proving injection-via-CDP still lands axe.
- `/mixed` — two regions (`#good` clean, `#bad` low-contrast) to exercise
  `within`/`excluding`/`skipping`/`according_to`.
- `/passing` — fully accessible, should be axe-clean under all default rules.

When adding behavior, add or extend a fixture rather than reaching for a real app. `reset_configuration!`
runs before each example and `Capybara.reset_sessions!` after.

## Conventions

- All Ruby files are `# frozen_string_literal: true`.
- Supports Ruby >= 3.0.
- The vendored `axe.min.js` is MPL-2.0 (Deque) and licensed separately from this gem's MIT code —
  keep `lib/axe/cuprite/vendor/axe-core-LICENSE.txt` alongside it and don't conflate the two
  licenses. `AXE_CORE_VERSION` in `version.rb` must stay in sync with the vendored file (the
  rake task does this).

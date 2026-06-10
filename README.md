# axe-cuprite

Run the [axe-core](https://github.com/dequelabs/axe-core) accessibility engine
against pages in your **Capybara system/feature tests driven by
[Cuprite](https://github.com/rubycdp/cuprite)** (the CDP/Ferrum headless-Chrome
driver) — and assert on the results with readable RSpec matchers.

The headline use case is **catching WCAG color-contrast regressions in CI**, but
you can run any axe rule.

```ruby
expect(page).to be_axe_clean.checking_only(:color_contrast)
```

## Why this gem exists

Deque's official `axe-core-capybara` / `axe-core-rspec` gems **do not work with
Cuprite**. To inject and run axe they reach for the underlying **Selenium**
`browser` object inside the Capybara driver. Cuprite has no Selenium browser, so
they break.

**axe-cuprite never touches Selenium-specific driver internals.** axe-core is
just a JavaScript file — a driver-agnostic engine — so we drive it exclusively
through Capybara's **driver-neutral** JavaScript API (`execute_script`,
`evaluate_async_script`), which Cuprite fully implements. That single decision is
what makes this gem work where the official one doesn't. As a bonus it stays
driver-agnostic (it works on any real-browser Capybara driver), but **Cuprite is
the primary, must-pass target.**

There is no runtime dependency on Selenium, Cuprite, or Ferrum — the only runtime
dependency is Capybara. You bring your own driver.

## Installation

```ruby
# Gemfile
group :test do
  gem "axe-cuprite"
end
```

```sh
bundle install
```

Then load the RSpec matchers from your `spec/spec_helper.rb` (or `rails_helper.rb`):

```ruby
require "axe/cuprite/rspec"
```

That mixes `be_axe_clean` / `be_accessible` into your example groups. If you only
want the framework-agnostic runner (no RSpec), `require "axe/cuprite"` instead.

## Usage

### The matcher

```ruby
RSpec.describe "Dashboard", type: :system do
  it "has no accessibility violations" do
    visit dashboard_path
    expect(page).to be_axe_clean
  end

  it "passes WCAG AA color contrast" do
    visit dashboard_path
    expect(page).to be_axe_clean.checking_only(:color_contrast)
  end
end
```

`be_accessible` is an alias for `be_axe_clean` — use whichever reads better.

### Chainable DSL

All chainers return the matcher, so they compose in any order:

| Method | What it does | axe concept |
| --- | --- | --- |
| `.within(*selectors)` | Only test inside these elements | context `include` |
| `.excluding(*selectors)` | Skip these elements | context `exclude` |
| `.checking_only(*rules)` | Run only these rules | `runOnly` type `rule` |
| `.according_to(*tags)` | Run only rules with these tags | `runOnly` type `tag` |
| `.skipping(*rules)` | Disable these rules | `rules: { id: { enabled: false } }` |
| `.with_options(hash)` | Merge raw axe run options (escape hatch) | — |
| `.with_timeout(seconds)` | Override the axe timeout for this assertion | — |

Rule ids and tags accept **either** friendly Ruby symbols **or** axe's own ids —
underscores and hyphens are normalized for you, so `:color_contrast` and
`"color-contrast"` are equivalent, as are `:best_practice` and `"best-practice"`.

```ruby
expect(page).to be_axe_clean
  .within("#main")
  .excluding(".third-party-widget")
  .according_to(:wcag2a, :wcag2aa)
  .skipping(:region)
```

> Note: `.checking_only` (specific rules) and `.according_to` (tags) are mutually
> exclusive — axe's `runOnly` accepts one or the other. Combining them raises an
> `ArgumentError`.

### Actionable failure messages

Failures are grouped by rule, with impact, help URL, the offending selector, and
an HTML snippet. For **color-contrast** violations they surface exactly what you
need to fix it:

```
expected page to be axe-clean, but found 1 violation across 1 element:

  ● [serious] color-contrast — Elements must meet minimum color contrast ratio thresholds (1 element)
    https://dequeuniversity.com/rules/axe/4.12/color-contrast
      - #faded
        <p id="faded" style="color:#585858; opacity:0.5; background:#ffffff;"> This text token passes…
        contrast 2.34:1 (needs 4.5:1) — fg #acacac on bg #ffffff, font 12pt/normal
```

### The runner (no RSpec required)

```ruby
results = AxeCuprite::Runner.new(page).run(
  context: "#main",
  options: { runOnly: { type: "rule", values: ["color-contrast"] } }
)

results.passes?               # => false
results.violations            # => [AxeCuprite::Violation, ...]
v = results.violations.first
v.id                          # => "color-contrast"
v.impact                      # => "serious"
node = v.nodes.first
node.selector                 # => "#faded"
cd = node.contrast_data       # => AxeCuprite::ContrastData (nil for non-contrast rules)
cd.contrast_ratio             # => 2.34
cd.expected_contrast_ratio    # => 4.5
cd.fg_color                   # => "#acacac"
cd.bg_color                   # => "#ffffff"
```

`context` maps to axe's context arg (a CSS selector string, or a hash with
`:include` / `:exclude`). `options` maps to axe's run options and is deep-merged
on top of your configured defaults. Only `violations` and `incomplete` are
carried back across the CDP boundary — the full results object (with
`passes`/`inapplicable`) can be huge.

## Configuration

```ruby
AxeCuprite.configure do |c|
  c.timeout         = 30          # seconds to wait for axe.run (see caveats)
  c.default_options = {}          # axe run options merged into every run
  c.default_tags    = %w[wcag2a wcag2aa]  # applied when no rule/tag scope is given
  c.skip_rules      = [:region]   # globally disabled rules
  c.auto_inject     = true        # (re)inject axe on demand inside #run
  c.report_only     = false       # log violations instead of failing (see below)
  c.include_html    = true        # include element HTML snippets in output (see below)
  c.logger          = Logger.new($stdout)
end
```

### Report-only mode

Set `report_only = true` to **log** violations instead of failing the example.
This eases incremental adoption on an existing app — you can see what axe finds
without turning the suite red. Negated assertions (`expect(page).not_to
be_axe_clean`) ignore this flag.

### Sensitive page content in output (`include_html`)

Both failure messages and `report_only` logs include a **truncated outer-HTML
snippet** (capped at 200 chars) of each offending element, so you can see *what*
failed at a glance. On suites that render real data — staging-backed tests,
seeded PII — those snippets can carry page content into CI logs or log
aggregation. This is normal for a testing tool, but if it matters to you:

- Point `c.logger` somewhere appropriate (a redacted sink, a dropped stream)
  rather than `$stdout`, so `report_only` output doesn't fan out to aggregation.
- Set `c.include_html = false` to drop the HTML snippets entirely. Output then
  carries only the rule id, impact, help URL, element **selector**, and the axe
  check message (for color-contrast, the fg/bg colors and ratio) — enough to
  locate and fix a violation without echoing page content. Note the selector
  itself can still reflect ids/classes from your markup.

## Caveats & engineering notes

### Timeout (decoupled from `default_max_wait_time`)

This is the subtle one. Ferrum's async evaluation wraps your promise in a
`setTimeout(reject, wait * 1000)` and **rejects with "timed out promise"** if it
doesn't resolve in time. Through Capybara's `evaluate_async_script`, that `wait`
is `Capybara.default_max_wait_time` — often 2 seconds, which `axe.run` on a real
page routinely exceeds.

axe-cuprite avoids this trap: on Cuprite it calls Ferrum's
`page.evaluate_async(script, explicit_wait, *args)` **directly**, with its own
timeout (default **30s**, configurable) that is completely **decoupled from
`default_max_wait_time`**. On non-Ferrum drivers it falls back to
`evaluate_async_script` under a temporarily-raised wait time. If axe still
doesn't finish, you get a clear `AxeCuprite::TimeoutError` telling you to raise
the timeout or scope the run with `.within`.

Tune it globally (`c.timeout = 60`) or per assertion (`.with_timeout(60)`).

### Content-Security-Policy

axe-cuprite's primary injection path is `execute_script`, which on Cuprite runs
via CDP `Runtime.evaluate` and is **not subject to the page's CSP** — so a strict
`script-src` policy generally doesn't block it (there's a test proving this). If
injection ever fails to land axe, the gem falls back to Ferrum's
`add_script_tag(content:)` and raises `AxeCuprite::InjectionError` with a
CSP-pointed message if even that fails.

### Idempotent injection

axe (~500KB) is injected once per page and guarded on
`typeof window.axe === 'undefined'`, so repeated assertions on the same page don't
re-inject. After a full navigation axe is gone; the runner detects the
"axe not defined" case and re-injects on demand. You can force a re-inject with
`AxeCuprite::Runner.new(page).inject!(force: true)`.

### Page readiness & iframes

axe runs against the DOM as it is the moment you assert — there are no implicit
sleeps. Assert on a fully loaded/settled page (after Turbo frames, etc.). axe
traverses **same-origin** iframes by default; cross-origin frames are inaccessible
to the engine.

## Updating the vendored axe-core engine

axe-core is **vendored** into the gem (`lib/axe/cuprite/vendor/axe.min.js`) — it
is never fetched at runtime. The current version is recorded in
`AxeCuprite::AXE_CORE_VERSION` and printed in the banner of the vendored file.

To refresh it:

```sh
rake 'axe:update[4.12.0]'   # pin a version
rake axe:update             # or grab the latest from npm
rake axe:version            # print the currently vendored version
rake axe:verify             # check axe.min.js against its recorded sha512
```

`axe:update` downloads the official `axe-core` tarball from
**registry.npmjs.org**, verifies it against the sha512 integrity the registry
publishes (aborting on any mismatch before writing a byte), extracts
`axe.min.js` and its `LICENSE`, and bumps the `AXE_CORE_VERSION` constant. The
sha512 of the vendored engine is recorded in
`lib/axe/cuprite/vendor/axe.min.js.sha512` so it can be re-checked at any time
with `rake axe:verify` (CI does this on every run). Note the bump in
`CHANGELOG.md`.

## Licensing

- **axe-cuprite's own code** is licensed under the **MIT** license — see
  [`LICENSE.txt`](LICENSE.txt).
- The **vendored axe-core engine** (`lib/axe/cuprite/vendor/axe.min.js`) is a
  separate work by Deque Systems, licensed under the **Mozilla Public License,
  version 2.0 (MPL-2.0)**. Its full license text ships alongside it at
  [`lib/axe/cuprite/vendor/axe-core-LICENSE.txt`](lib/axe/cuprite/vendor/axe-core-LICENSE.txt).

The two licenses are kept distinct and apply to their respective files.

## Development

```sh
bundle install
bundle exec rspec   # runs the suite under Cuprite (requires Chrome/Chromium)
```

The gem's own test suite uses Capybara + Cuprite against a tiny static fixture
app, including a known-bad `opacity`-induced contrast page, to prove the
no-Selenium path end to end.

## Out of scope

- Static template/CSS analysis (this is render-time only, by design).
- Selenium/Watir support (the official `axe-core-*` gems already cover those).
- Auto-fixing violations.

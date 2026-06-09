# frozen_string_literal: true

# A tiny Rack app serving static HTML fixtures, booted by Capybara and driven
# by Cuprite. No Sinatra needed — keeps the dependency surface minimal.
class FixtureApp
  # A fully accessible page: lang, title, single main landmark, one h1,
  # high-contrast text. Should be axe-clean under all default rules.
  PASSING = <<~HTML
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Passing fixture</title></head>
    <body>
      <main>
        <h1>Accessible page</h1>
        <p style="color:#111111; background:#ffffff;">
          High contrast text that comfortably passes WCAG AA.
        </p>
      </main>
    </body>
    </html>
  HTML

  # The headline case: #585858 text passes contrast on its own (~7.7:1), but
  # opacity:0.5 composites it toward #ababab over white, dropping it to ~2.3:1
  # — well below the 4.5:1 AA requirement. Only color-contrast should fail here.
  BAD_CONTRAST = <<~HTML
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Bad contrast fixture</title></head>
    <body>
      <main>
        <h1>Contrast problem</h1>
        <p id="faded" style="color:#585858; opacity:0.5; background:#ffffff;">
          This text token passes alone but fails once opacity is composited.
        </p>
      </main>
    </body>
    </html>
  HTML

  # Two regions: #good is clean, #bad has a low-contrast paragraph. Used to
  # exercise within / excluding / skipping / according_to.
  MIXED = <<~HTML
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Mixed fixture</title></head>
    <body>
      <main>
        <h1>Mixed</h1>
        <section id="good">
          <p style="color:#111111; background:#ffffff;">Readable paragraph.</p>
        </section>
        <section id="bad">
          <p style="color:#999999; background:#ffffff;">Low contrast paragraph (~2.8:1).</p>
        </section>
      </main>
    </body>
    </html>
  HTML

  # A strict Content-Security-Policy (no 'unsafe-inline', no 'unsafe-eval') over
  # the bad-contrast markup. Proves injection-via-CDP still lands axe and finds
  # the violation even when the page forbids inline/eval scripts.
  CSP = <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self'; style-src 'unsafe-inline'">
      <title>CSP fixture</title>
    </head>
    <body>
      <main>
        <h1>Locked down</h1>
        <p style="color:#585858; opacity:0.5; background:#ffffff;">
          Inline scripts are forbidden here, but axe still runs via CDP.
        </p>
      </main>
    </body>
    </html>
  HTML

  ROUTES = {
    "/passing" => PASSING,
    "/bad_contrast" => BAD_CONTRAST,
    "/mixed" => MIXED,
    "/csp" => CSP
  }.freeze

  def call(env)
    body = ROUTES.fetch(env["PATH_INFO"],
                        '<!doctype html><html lang="en"><head><title>Not found</title></head><body><main><h1>Not found</h1></main></body></html>')
    [200, { "content-type" => "text/html; charset=utf-8" }, [body]]
  end
end

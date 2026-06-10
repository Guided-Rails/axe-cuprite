# frozen_string_literal: true

module AxeCuprite
  # Version of the axe-cuprite gem itself.
  VERSION = "0.2.0"

  # Version of the axe-core engine vendored under lib/axe/cuprite/vendor/axe.min.js.
  # Keep this in sync with the vendored file via `rake axe:update`.
  AXE_CORE_VERSION = "4.12.0"
end

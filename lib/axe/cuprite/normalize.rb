# frozen_string_literal: true

module AxeCuprite
  # Normalizes rule ids and tags so callers can use friendly Ruby symbols
  # (:color_contrast) interchangeably with axe's own ids ("color-contrast").
  module Normalize
    module_function

    # :color_contrast / "color_contrast" / "color-contrast" -> "color-contrast"
    def rule(id)
      id.to_s.strip.tr("_", "-")
    end

    # :wcag2aa -> "wcag2aa"; :best_practice -> "best-practice"
    def tag(value)
      value.to_s.strip.tr("_", "-")
    end

    def rules(list)
      Array(list).map { |r| rule(r) }
    end

    def tags(list)
      Array(list).map { |t| tag(t) }
    end
  end
end

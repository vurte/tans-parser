# frozen_string_literal: true

module TansParser
  # Describes a recognized UI element on the terminal screen.
  Element = Struct.new(
    :role,
    :text,
    :row, :col,
    :width, :height,
    :checked,
    :focused,
    :fg, :bg,
    keyword_init: true,
  ) do
    def to_h
      {
        role: role,
        text: text,
        row: row, col: col,
        width: width, height: height,
        checked: checked,
        focused: focused,
        fg: fg, bg: bg,
      }.compact
    end
  end
end

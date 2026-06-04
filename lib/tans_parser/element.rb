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
    :disabled,
    keyword_init: true,
  ) do
    def checked?
      !!checked
    end

    def disabled?
      !!disabled
    end

    def bounds
      { row: row, col: col, width: width, height: height }
    end

    def click
      { action: :click, target: self, row: row, col: col + (width / 2) }
    end

    def type(text)
      { action: :type, target: self, row: row, col: col + (width / 2), text: text }
    end

    def press_key(key)
      { action: :press_key, target: self, key: key }
    end

    def to_h
      {
        role: role,
        text: text,
        row: row, col: col,
        width: width, height: height,
        checked: checked,
        focused: focused,
        fg: fg, bg: bg,
        disabled: disabled,
      }.compact
    end
  end
end

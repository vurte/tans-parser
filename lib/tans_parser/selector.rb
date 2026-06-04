# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/ClassLength

module TansParser
  # Scans terminal state for recognized UI elements.
  #
  #   selector = Selector.new(state)
  #   selector.get_by_text("OK")       # => [Element, ...]
  #   selector.get_by_role(:button)    # => [Element, ...]
  #   selector.buttons                 # => [Element, ...]
  #   selector.dialogs                 # => [Element, ...]
  #   selector.button(text: "OK")      # => Element or nil
  #
  class Selector
    TOP_LEFT_CORNERS = /[┌┏┎┍]/
    BOTTOM_LEFT_CORNERS = %w[└ ┗ ┖ ┕ ╰ ╚].freeze
    BOTTOM_RIGHT_CORNERS = %w[┘ ┛ ┚ ┙ ╯ ╝].freeze

    attr_reader :state, :elements

    def initialize(state)
      @state = state.is_a?(State) ? state : State.new(state)
      @elements = scan
    end

    # Find elements by visible text (partial match).
    def get_by_text(text)
      @elements.select { |e| e.text&.include?(text) }
    end

    # Find elements by role with optional filters.
    # rubocop:disable Metrics/CyclomaticComplexity
    def get_by_role(role, text: nil, checked: nil, disabled: nil)
      results = @elements.select { |e| e.role == role.to_sym }
      results = results.select { |e| e.text.to_s.include?(text.to_s) } if text
      results = results.select { |e| e.checked == checked } unless checked.nil?
      results = results.select { |e| e.disabled == disabled } unless disabled.nil?
      results
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    # Convenience accessors (plural — return arrays)
    def buttons(**filters)
      get_by_role(:button, **filters)
    end

    def checkboxes(**filters)
      get_by_role(:checkbox, **filters)
    end

    def dialogs(**filters)
      get_by_role(:dialog, **filters)
    end

    def inputs(**filters)
      get_by_role(:input, **filters)
    end

    def labels(**filters)
      get_by_role(:label, **filters)
    end

    def menus(**filters)
      get_by_role(:menu, **filters)
    end

    def tabs(**filters)
      get_by_role(:tab, **filters)
    end

    def statusbars(**filters)
      get_by_role(:statusbar, **filters)
    end

    def progress_bars(**filters)
      get_by_role(:progress, **filters)
    end

    # Convenience accessors (singular — return first element or nil)
    def button(**filters)
      buttons(**filters).first
    end

    def checkbox(**filters)
      checkboxes(**filters).first
    end

    def dialog(**filters)
      dialogs(**filters).first
    end

    def input(**filters)
      inputs(**filters).first
    end

    def label(**filters)
      labels(**filters).first
    end

    def menu(**filters)
      menus(**filters).first
    end

    def tab(**filters)
      tabs(**filters).first
    end

    def statusbar(**filters)
      statusbars(**filters).first
    end

    def progress_bar(**filters)
      progress_bars(**filters).first
    end

    # Scope subsequent searches to a specific element's bounding box.
    def within(element, &block)
      scoped = ScopedSelector.new(self, element)
      if block
        yield scoped
      else
        scoped
      end
    end

    private

    def grid
      @state.grid
    end

    def scan
      results = []
      results.concat(detect_tabs)
      results.concat(detect_inputs)
      results.concat(detect_buttons)
      results.concat(detect_checkboxes)
      results.concat(detect_dialogs)
      results.concat(detect_labels)
      results.concat(detect_menus)
      results.concat(detect_statusbars)
      results.concat(detect_progress_bars)
      results
    end

    # Detects buttons: [ OK ], (Cancel), <Submit>
    # Skips underscore-only brackets (those are inputs).
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def detect_buttons
      buttons = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        scan_match = line.enum_for(:scan, /\[([^\]]+)\]|\(([^)]+)\)|<([^>]+)>/)
        scan_match.each do
          text = (::Regexp.last_match(1) || ::Regexp.last_match(2) || ::Regexp.last_match(3)).to_s.strip
          next if text.empty?
          next if text.match?(/^_+$/)
          next if text.match?(/^[ xX*]$/) # skip checkbox markers

          col = ::Regexp.last_match.begin(0)
          buttons << Element.new(
            role: :button,
            text: text,
            row: r, col: col,
            width: ::Regexp.last_match[0].length, height: 1,
            fg: row[col][:fg],
            bg: row[col][:bg],
          )
        end
      end
      buttons
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Detects checkboxes: [x], [*], [ ] at start of lines
    def detect_checkboxes
      checkboxes = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        match = line.match(/^(\s*)\[([ xX*])\]\s+(.+)/)
        next unless match

        checked = match[2] != " "
        label_text = match[3].strip
        col = match.begin(3)
        checkboxes << Element.new(
          role: :checkbox,
          text: label_text,
          row: r, col: col,
          width: label_text.length, height: 1,
          checked: checked,
        )
      end
      checkboxes
    end

    # Detects dialogs: regions enclosed by box-drawing characters
    def detect_dialogs
      dialogs = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        tl_idx = 0
        while (tl_idx = line.index(TOP_LEFT_CORNERS, tl_idx))
          width = dialog_top_width(line, tl_idx)
          unless width
            tl_idx += 1
            next
          end

          bottom_r = dialog_bottom_row(tl_idx, width, r + 1)
          if bottom_r
            height = bottom_r - r + 1
            text = extract_dialog_text(r + 1, tl_idx + 1, width - 2, height - 2)
            dialogs << Element.new(
              role: :dialog,
              text: text,
              row: r, col: tl_idx,
              width: width, height: height,
            )
          end
          tl_idx += 1
        end
      end
      dialogs
    end

    # Returns the width of a dialog top border if valid, nil otherwise
    def dialog_top_width(line, tl_idx)
      top_row = line[tl_idx..]
      tr_match = top_row.match(/^[┌┏┎┍]([─━]*)([┐┓┒┑])/)
      return nil unless tr_match

      tr_match[0].length
    end

    # Returns the row index of a matching bottom border, nil if not found
    def dialog_bottom_row(tl_idx, width, start_row)
      r = start_row
      while r < grid.length
        bottom_line = grid[r].map { |c| c[:char] }.join
        bot_left = bottom_line[tl_idx]
        if BOTTOM_LEFT_CORNERS.include?(bot_left) && bottom_line[tl_idx + width - 1]
          bot_right = bottom_line[tl_idx + width - 1]
          return r if BOTTOM_RIGHT_CORNERS.include?(bot_right)
        end
        r += 1
      end
      nil
    end

    # Extracts visible text from inside a dialog
    def extract_dialog_text(start_row, start_col, inner_width, inner_height)
      lines = []
      (start_row...[start_row + inner_height, grid.length].min).each do |r|
        row = grid[r]
        slice = row[start_col, [inner_width, row.length - start_col].min]
        line = slice.map { |c| c[:char] }.join.rstrip
        lines << line unless line.empty?
      end
      lines.join(" ").strip
    end

    # Detects statusbar: bottom row with reversed/inverse colors
    def detect_statusbars
      bars = []
      return bars if grid.empty?

      last_row_idx = grid.length - 1
      last_row = grid[last_row_idx]

      non_default = last_row.reject { |c| c[:bg] == "default" }
      return bars if non_default.length < 3

      text = last_row.map { |c| c[:char] }.join.strip
      return bars if text.empty?

      bars << Element.new(
        role: :statusbar,
        text: text,
        row: last_row_idx, col: 0,
        width: last_row.length, height: 1,
        bg: non_default.first[:bg],
      )
      bars
    end

    # Detects progress bars: [####   ] or [=====>  ] patterns
    def detect_progress_bars
      bars = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        match = line.match(/\[([#>=-]+)\s*\]/)
        next unless match

        filled = match[1]
        total = match[0].length - 2
        percent = (filled.length.to_f / total * 100).round
        bars << Element.new(
          role: :progress,
          text: "#{percent}%",
          row: r, col: ::Regexp.last_match.begin(0),
          width: match[0].length, height: 1,
          checked: percent == 100,
        )
      end
      bars
    end

    # Detects text inputs: [____] underscore-filled brackets
    def detect_inputs
      inputs = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        line.enum_for(:scan, /\[(_+)\]/).each do
          m = ::Regexp.last_match
          col = m.begin(0)
          inputs << Element.new(
            role: :input,
            text: "",
            row: r, col: col,
            width: m[0].length, height: 1,
          )
        end
      end
      inputs
    end

    # Detects labels: text followed by colon separator
    def detect_labels
      labels = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        match = line.match(/\b([A-Za-z]\w*(?:\s+\w+)*\s*:)/)
        next unless match

        label_text = match[1].strip.sub(/:$/, "").strip
        next if label_text.empty? || label_text.length < 2

        col = match.begin(1)
        labels << Element.new(
          role: :label,
          text: label_text,
          row: r, col: col,
          width: match[1].length, height: 1,
        )
      end
      labels
    end

    # Detects menus: top-row menu bars and > dropdown items
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def detect_menus
      menus = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        stripped = line.strip
        next if stripped.empty?

        # Menu bar on first two rows: words separated by 2+ spaces
        if r <= 1
          items = stripped.split(/\s{2,}/)
          if items.length >= 2 && items.all? { |i| i.match?(/^[A-Za-z]/) }
            col = line.index(stripped)
            menus << Element.new(
              role: :menu,
              text: items.join(" | "),
              row: r, col: col || 0,
              width: line.length, height: 1,
            )
          end
        end

        # Dropdown item: > prefix
        line.enum_for(:scan, /(>\s*[A-Za-z][\w\s]*)/).each do
          m = ::Regexp.last_match
          menus << Element.new(
            role: :menu,
            text: m[0].sub(/^>\s*/, "").strip,
            row: r, col: m.begin(0),
            width: m[0].length, height: 1,
          )
        end
      end
      menus
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # Detects tabs: multiple closely-spaced [bracketed] items on one row
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def detect_tabs
      tabs = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        matches = line.enum_for(:scan, /\[([^\]]+)\]/).map { ::Regexp.last_match }
        next if matches.length < 2

        gaps_close = matches.each_cons(2).all? { |a, b| b.begin(0) - a.end(0) <= 3 }
        next unless gaps_close

        matches.each do |m|
          tab_text = m[1].strip
          next if tab_text.empty? || tab_text.match?(/^_+$/)

          cell = row[m.begin(0)]
          focused = cell[:underline] || cell[:bg] != "default"
          tabs << Element.new(
            role: :tab,
            text: tab_text,
            row: r, col: m.begin(0),
            width: m[0].length, height: 1,
            focused: focused,
          )
        end
      end
      tabs
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/ClassLength

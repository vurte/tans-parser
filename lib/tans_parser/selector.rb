# frozen_string_literal: true

module TansParser
  # Scans terminal state for recognized UI elements.
  #
  #   selector = Selector.new(state)
  #   selector.get_by_text("OK")       # => [Element, ...]
  #   selector.get_by_role(:button)    # => [Element, ...]
  #   selector.buttons                 # => [Element, ...]
  #   selector.dialogs                 # => [Element, ...]
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

    # Find elements by role.
    def get_by_role(role)
      @elements.select { |e| e.role == role.to_sym }
    end

    # Convenience accessors
    def buttons
      get_by_role(:button)
    end

    def checkboxes
      get_by_role(:checkbox)
    end

    def dialogs
      get_by_role(:dialog)
    end

    def statusbars
      get_by_role(:statusbar)
    end

    def progress_bars
      get_by_role(:progress)
    end

    private

    def grid
      @state.grid
    end

    def scan
      results = []
      results.concat(detect_buttons)
      results.concat(detect_checkboxes)
      results.concat(detect_dialogs)
      results.concat(detect_statusbars)
      results.concat(detect_progress_bars)
      results
    end

    # Detects buttons: [ OK ], (Cancel), <Submit>
    # rubocop:disable Metrics/AbcSize
    def detect_buttons
      buttons = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        scan_match = line.enum_for(:scan, /\[([^\]]+)\]|\(([^)]+)\)|<([^>]+)>/)
        scan_match.each do
          text = (::Regexp.last_match(1) || ::Regexp.last_match(2) || ::Regexp.last_match(3)).to_s.strip
          next if text.empty?

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
    # rubocop:enable Metrics/AbcSize

    # Detects checkboxes: [x], [*], [ ] at start of lines
    def detect_checkboxes
      checkboxes = []
      grid.each_with_index do |row, r|
        line = row.map { |c| c[:char] }.join
        match = line.match(/^(\s*)\[([ xX*])\]\s+(.+)/)
        next unless match

        checked = match[2] != " "
        label = match[3].strip
        col = match.begin(3)
        checkboxes << Element.new(
          role: :checkbox,
          text: label,
          row: r, col: col,
          width: label.length, height: 1,
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
  end
end

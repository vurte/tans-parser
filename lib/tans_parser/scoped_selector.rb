# frozen_string_literal: true

require "timeout"

module TansParser
  # Scoped view of a terminal screen restricted to an element's bounding box.
  # Created by Selector#within(element).
  #
  #   selector.within(dialog) do |scope|
  #     scope.buttons       # only buttons inside the dialog
  #     scope.find_text("OK")
  #   end
  class ScopedSelector
    attr_reader :element

    def initialize(selector, element)
      @selector = selector
      @element = element
      @state = selector.state
      @row_start = element.row
      @row_end = element.row + element.height - 1
      @col_start = element.col
      @col_end = element.col + element.width - 1
    end

    # Find elements by role, scoped to the bounding box.
    def get_by_role(role, text: nil, checked: nil, disabled: nil)
      @selector.get_by_role(role, text: text, checked: checked, disabled: disabled)
               .select { |e| fully_within?(e) }
    end

    # Find elements by visible text, scoped to the bounding box.
    def get_by_text(text)
      @selector.get_by_text(text)
               .select { |e| fully_within?(e) }
    end

    # Search for text, scoped to the bounding box.
    def find_text(pattern, match: :partial)
      results = []
      grid = @state.grid
      max_row = [@row_end, grid.length - 1].min
      max_col = [@col_end, grid[0].length - 1, 0].max

      (@row_start..max_row).each do |r|
        row = grid[r]
        slice = row[@col_start..max_col]

        row_text = slice.map { |c| c[:char] }.join
        find_in_row(pattern, match, r, row_text, results)
      end
      results
    end

    # Convenience plural accessors
    def buttons(**filters)    = get_by_role(:button, **filters)
    def checkboxes(**filters) = get_by_role(:checkbox, **filters)
    def dialogs(**filters)    = get_by_role(:dialog, **filters)
    def inputs(**filters)     = get_by_role(:input, **filters)
    def labels(**filters)     = get_by_role(:label, **filters)
    def menus(**filters)      = get_by_role(:menu, **filters)
    def tabs(**filters)       = get_by_role(:tab, **filters)
    def statusbars(**filters) = get_by_role(:statusbar, **filters)
    def progress_bars(**filters) = get_by_role(:progress, **filters)

    # Convenience singular accessors
    def button(**filters)    = buttons(**filters).first
    def checkbox(**filters)  = checkboxes(**filters).first
    def dialog(**filters)    = dialogs(**filters).first
    def input(**filters)     = inputs(**filters).first
    def label(**filters)     = labels(**filters).first
    def menu(**filters)      = menus(**filters).first
    def tab(**filters)       = tabs(**filters).first
    def statusbar(**filters) = statusbars(**filters).first
    def progress_bar(**filters) = progress_bars(**filters).first

    private

    def fully_within?(elem)
      elem.row.between?(@row_start, @row_end) &&
        elem.col >= @col_start &&
        elem.col <= @col_end
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def find_in_row(pattern, match, row_idx, row_text, results)
      case match
      when :partial
        compiled = pattern.is_a?(Regexp) ? pattern : Regexp.new(Regexp.escape(pattern.to_s))
        find_regex_in_text(compiled, row_idx, row_text, results)
      when :exact
        pattern_str = pattern.is_a?(Regexp) ? pattern.source : pattern.to_s
        return unless row_text.strip == pattern_str

        results << { row: row_idx, col: @col_start, text: row_text.rstrip, full_line: row_text }
      when :regex
        compiled = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
        find_regex_in_text(compiled, row_idx, row_text, results)
      else
        raise ArgumentError, "unknown match mode: #{match.inspect}. Use :partial, :exact, or :regex"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def find_regex_in_text(compiled, row_idx, text, results)
      pos = 0
      begin
        Timeout.timeout(State::TEXT_SEARCH_TIMEOUT) do
          while (m = text.match(compiled, pos))
            results << { row: row_idx, col: @col_start + m.begin(0), text: m[0], full_line: text }
            pos = m.begin(0) + 1
          end
        end
      rescue Timeout::Error
        # Stop processing on timeout — return partial results
      end
    end
  end
end

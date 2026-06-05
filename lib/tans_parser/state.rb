# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

require "timeout"

module TansParser
  # Represents the parsed state of a terminal screen.
  # Provides high-level query methods for AI consumption.
  class State
    attr_reader :rows, :cols, :grid, :cursor, :cursor_visible, :cursor_style, :mouse_mode, :mouse_format, :annotations

    def initialize(data)
      raise ArgumentError, "State data must include :size key" unless data[:size]
      raise ArgumentError, "State data must include :rows key" unless data[:rows]

      @rows = data[:size][:rows]
      @cols = data[:size][:cols]
      @grid = data[:rows]
      @cursor = data[:cursor]

      cursor_info = data[:cursor].is_a?(Hash) ? data[:cursor] : {}
      @cursor_visible = data.key?(:cursor_visible) ? data[:cursor_visible] : (cursor_info[:visible] != false)
      @cursor_style = data.key?(:cursor_style) ? data[:cursor_style] : (cursor_info[:style] || 1)

      @mouse_mode = data[:mouse_mode] || :none
      @mouse_format = data[:mouse_format] || :normal

      @annotations = data[:annotations] || []
    end

    # Annotate a region of the terminal with a semantic role.
    # These annotations are picked up by Selector during element recognition.
    # rubocop:disable Metrics/ParameterLists
    def annotate_role(role, row:, col:, width: 1, height: 1, text: nil, **extra)
      @annotations << { role: role.to_sym, row: row, col: col,
                        width: width, height: height, text: text, }.merge(extra)
    end
    # rubocop:enable Metrics/ParameterLists

    # Get plain text of the entire terminal (no ANSI)
    def plain_text
      @grid.map { |row| row.map { |c| c[:char] }.join.rstrip }.join("\n")
    end

    # Get text at a specific position
    def text_at(row, col, length = @cols - col)
      return "" if row >= @rows || col >= @cols

      @grid[row][col, length].map { |c| c[:char] }.join
    end

    # Search for text across the entire terminal.
    # For regex patterns, matching is bounded by a timeout to prevent ReDoS.
    #
    #   state.find_text("hello")                  # partial match (default)
    #   state.find_text("hello", match: :exact)   # exact row match
    #   state.find_text("\\d+", match: :regex)    # regex from string
    #   state.find_text(/\\d{3}/)                 # Regexp object (partial mode)
    #
    # Returns [{ row:, col:, text:, full_line: }, ...].
    # +text+ is the actual matched substring (for Regexp/:regex mode)
    # or the pattern string (for :partial/:exact with String).
    TEXT_SEARCH_TIMEOUT = 5

    def find_text(pattern, match: :partial)
      unless %i[partial exact regex].include?(match)
        raise ArgumentError, "unknown match mode: #{match.inspect}. Use :partial, :exact, or :regex"
      end

      results = []
      case match
      when :exact
        find_text_exact(pattern, results)
      else
        compiled = compile_pattern(pattern, match)
        find_text_with_regex(compiled, results)
      end
      results
    end

    # Get the color at a specific cell
    def foreground_at(row, col)
      return nil if row >= @rows || col >= @cols

      @grid[row][col][:fg]
    end

    def background_at(row, col)
      return nil if row >= @rows || col >= @cols

      @grid[row][col][:bg]
    end

    def style_at(row, col)
      return nil if row >= @rows || col >= @cols

      cell = @grid[row][col]
      { bold: cell[:bold], italic: cell[:italic], underline: cell[:underline] }
    end

    def to_ai_json
      h = extract_highlights
      cursor_info = @cursor.is_a?(Hash) ? @cursor : {}
      r = cursor_info[:row] || cursor_info["row"] || 0
      c = cursor_info[:col] || cursor_info["col"] || 0
      styled_count = h.count { |hl| hl[:bold] || hl[:italic] || hl[:underline] || hl[:fg] || hl[:bg] }

      summary = "Cursor at [#{r},#{c}]. "
      summary << "#{styled_count} styled row#{"s" unless styled_count == 1}"
      fgs = h.flat_map { |hl| hl[:fg] }.compact.uniq
      bgs = h.flat_map { |hl| hl[:bg] }.compact.uniq
      summary << ", colors: fg=#{fgs.sort.join(",")}" unless fgs.empty?
      summary << ", bg=#{bgs.sort.join(",")}" unless bgs.empty?
      summary << "."

      {
        size: { rows: @rows, cols: @cols },
        cursor: cursor_info,
        text: plain_text,
        highlights: h,
        summary: summary,
      }
    end

    DEFAULT_CELL = { char: " ", fg: "default", bg: "default",
                     bold: false, italic: false, underline: false, blink: false, }.freeze

    # Compare this state with another State and return cell-level differences.
    # With chars_only: true, only differences in the :char key are reported.
    def diff(other_state, chars_only: false)
      other = other_state.is_a?(State) ? other_state : State.new(other_state)
      max_rows = [@rows, other.rows].max
      max_cols = [@cols, other.cols].max
      results = []

      (0...max_rows).each do |r|
        (0...max_cols).each do |c|
          a = cell_at(r, c)
          b = other.send(:cell_at, r, c)
          next if chars_only ? a[:char] == b[:char] : a == b

          results << { row: r, col: c, before: a, after: b }
        end
      end
      results
    end

    private

    def extract_highlights
      highlights = []
      @grid.each_with_index do |row, ri|
        row_text = row.map { |c| c[:char] }.join
        next if row_text.strip.empty?

        fgs = row.map { |c| c[:fg] || c["fg"] || "default" }
                 .uniq.reject { |c| c == "default" }
        bgs = row.map { |c| c[:bg] || c["bg"] || "default" }
                 .uniq.reject { |c| c == "default" }
        bold = row.any? { |c| c[:bold] || c["bold"] }
        italic = row.any? { |c| c[:italic] || c["italic"] }
        underline = row.any? { |c| c[:underline] || c["underline"] }

        next if fgs.empty? && bgs.empty? && !bold && !italic && !underline

        h = { row: ri, text: row_text }
        h[:bold] = true if bold
        h[:italic] = true if italic
        h[:underline] = true if underline
        h[:fg] = fgs.size == 1 ? fgs.first : fgs unless fgs.empty?
        h[:bg] = bgs.size == 1 ? bgs.first : bgs unless bgs.empty?
        highlights << h
      end
      highlights
    end

    def compile_pattern(pattern, match)
      return pattern if pattern.is_a?(Regexp)

      source = match == :regex ? pattern.to_s : Regexp.escape(pattern.to_s)
      Regexp.new(source)
    end

    def find_text_exact(pattern, results)
      pattern_str = pattern.is_a?(Regexp) ? pattern.source : pattern.to_s
      @grid.each_with_index do |row, ri|
        row_text = row.map { |c| c[:char] }.join.rstrip
        next unless row_text == pattern_str

        results << { row: ri, col: 0, text: row_text, full_line: row_text }
      end
    end

    def find_text_with_regex(compiled, results)
      @grid.each_with_index do |row, ri|
        text = row.map { |c| c[:char] }.join
        pos = 0
        begin
          Timeout.timeout(TEXT_SEARCH_TIMEOUT) do
            while (m = text.match(compiled, pos))
              results << { row: ri, col: m.begin(0), text: m[0], full_line: text }
              pos = m.begin(0) + 1
            end
          end
        rescue Timeout::Error
          # Stop processing on timeout — return partial results
        end
      end
    end

    def cell_at(row, col)
      if row < @rows && col < @cols
        @grid[row][col]
      else
        DEFAULT_CELL
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

require "timeout"

module TansParser
  # Represents the parsed state of a terminal screen.
  # Provides high-level query methods for AI consumption.
  class State
    attr_reader :rows, :cols, :grid, :cursor, :cursor_visible, :cursor_style, :mouse_mode, :mouse_format

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
    end

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
    TEXT_SEARCH_TIMEOUT = 5

    def find_text(pattern)
      results = []
      is_regex = pattern.is_a?(Regexp)

      @grid.each_with_index do |row, ri|
        text = row.map { |c| c[:char] }.join
        pos = 0
        begin
          if is_regex
            Timeout.timeout(TEXT_SEARCH_TIMEOUT) do
              while (match = text.index(pattern, pos))
                results << { row: ri, col: match, text: pattern.to_s, full_line: text }
                pos = match + 1
              end
            end
          else
            while (match = text.index(pattern, pos))
              results << { row: ri, col: match, text: pattern, full_line: text }
              pos = match + 1
            end
          end
        rescue Timeout::Error
          # Stop processing on timeout — return partial results
        end
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
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

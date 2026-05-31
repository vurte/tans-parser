# frozen_string_literal: true

module TansParser
  # Parses raw terminal output (ANSI escape sequences + text) into a
  # structured state representation.
  #
  # Handles:
  # - SGR (Select Graphic Rendition) — colors, bold, italic, underline
  # - Cursor movement (CUU, CUD, CUF, CUB, CUP)
  # - Erase (ED, EL)
  # - Line feed, carriage return, backspace, tab
  #
  # Output: {rows: [[{char, fg, bg, bold, italic, underline}]], cursor: {row, col}, size: {rows, cols}}
  #
  # rubocop:disable Metrics/ModuleLength
  module ANSIParser
    SGR_COLORS = {
      0 => :reset,
      1 => :bold,
      3 => :italic,
      4 => :underline,
      5 => :blink,
      7 => :reverse,
      22 => :normal,
      23 => :no_italic,
      24 => :no_underline,
      30 => :black,
      31 => :red,
      32 => :green,
      33 => :yellow,
      34 => :blue,
      35 => :magenta,
      36 => :cyan,
      37 => :white,
      38 => :xterm_fg,  # 38;5;N or 38;2;R;G;B
      39 => :default_fg,
      40 => :bg_black,
      41 => :bg_red,
      42 => :bg_green,
      43 => :bg_yellow,
      44 => :bg_blue,
      45 => :bg_magenta,
      46 => :bg_cyan,
      47 => :bg_white,
      48 => :xterm_bg,  # 48;5;N or 48;2;R;G;B
      49 => :default_bg,
      90 => :bright_black,
      91 => :bright_red,
      92 => :bright_green,
      93 => :bright_yellow,
      94 => :bright_blue,
      95 => :bright_magenta,
      96 => :bright_cyan,
      97 => :bright_white,
      100 => :bg_bright_black,
      101 => :bg_bright_red,
      102 => :bg_bright_green,
      103 => :bg_bright_yellow,
      104 => :bg_bright_blue,
      105 => :bg_bright_magenta,
      106 => :bg_bright_cyan,
      107 => :bg_bright_white,
    }.freeze

    SGR_16_TO_NAME = {
      0 => "black",
      1 => "red",
      2 => "green",
      3 => "yellow",
      4 => "blue",
      5 => "magenta",
      6 => "cyan",
      7 => "white",
      8 => "bright_black",
      9 => "bright_red",
      10 => "bright_green",
      11 => "bright_yellow",
      12 => "bright_blue",
      13 => "bright_magenta",
      14 => "bright_cyan",
      15 => "bright_white",
    }.freeze

    DEC_MAP = {
      "`" => "◆",
      "a" => "▒",
      "b" => "\u2409",
      "c" => "\u240C",
      "d" => "\u240D",
      "e" => "\u240A",
      "f" => "°",
      "g" => "±",
      "h" => "\u2424",
      "i" => "\u240B",
      "j" => "┘",
      "k" => "┐",
      "l" => "┌",
      "m" => "└",
      "n" => "┼",
      "o" => "⎺",
      "p" => "⎻",
      "q" => "─",
      "r" => "⎼",
      "s" => "⎽",
      "t" => "├",
      "u" => "┤",
      "v" => "┴",
      "w" => "┬",
      "x" => "│",
      "y" => "≤",
      "z" => "≥",
      "{" => "π",
      "|" => "≠",
      "}" => "£",
      "~" => "·",
    }.freeze

    # Parse raw terminal output into a structured state Hash
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockNesting
    def self.parse(raw, rows = 40, cols = 120)
      grid = Array.new(rows) do
        Array.new(cols) { default_cell.dup }
      end

      cursor = { row: 0, col: 0 }
      attrs = { fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: false }
      saved_cursor = nil
      scroll_region = { top: 0, bottom: rows - 1 }
      pending_dsr = false

      normal_grid = grid
      alt_grid = nil

      normal_cursor = cursor
      alt_cursor = { row: 0, col: 0 }

      normal_saved_cursor = nil
      alt_saved_cursor = nil

      use_alt_screen = false

      cursor_visible = true
      cursor_style = 1 # 1 = blinking block (default)

      g0_charset = :ascii
      g1_charset = :dec
      active_charset = :g0

      mouse_mode = :none
      mouse_format = :normal

      # Strip everything before the last full clear (if any)
      # to avoid accumulated garbage
      processed = raw

      i = 0
      while i < processed.length
        if processed[i] == "\e" && processed[i + 1] == "["
          # Find end of CSI sequence
          j = i + 2
          j += 1 while j < processed.length && !processed[j].match?(/[A-HJ-KP-SX@`fhlmnRrsuq]/)
          seq = processed[i..j]

          dsr, new_saved, action = _apply_csi(seq, cursor, attrs, grid, rows, cols, saved_cursor, scroll_region)
          pending_dsr ||= dsr

          if new_saved
            if use_alt_screen
              alt_saved_cursor = new_saved
              saved_cursor = alt_saved_cursor
            else
              normal_saved_cursor = new_saved
              saved_cursor = normal_saved_cursor
            end
          end

          if action.key?(:alt_screen)
            new_alt = action[:alt_screen]
            code = action[:alt_screen_code]
            if new_alt != use_alt_screen
              if new_alt
                # Switch to Alternate Screen
                # Save normal cursor
                normal_cursor = { row: cursor[:row], col: cursor[:col] }

                # Lazy initialize alt grid
                alt_grid ||= Array.new(rows) do
                  Array.new(cols) { default_cell.dup }
                end

                # For \e[?1049h, clear alternate screen and reset cursor to 0,0
                if code == 1049
                  alt_grid = Array.new(rows) do
                    Array.new(cols) { default_cell.dup }
                  end
                  alt_cursor = { row: 0, col: 0 }
                end

                grid = alt_grid
                cursor = alt_cursor
                saved_cursor = alt_saved_cursor
                use_alt_screen = true
              else
                # Switch to Normal Screen
                # Save alt cursor
                alt_cursor = { row: cursor[:row], col: cursor[:col] }

                grid = normal_grid
                cursor = normal_cursor
                saved_cursor = normal_saved_cursor
                use_alt_screen = false
              end
            end
          end

          cursor_visible = action[:cursor_visible] if action.key?(:cursor_visible)

          cursor_style = action[:cursor_style] if action.key?(:cursor_style)

          mouse_mode = action[:mouse_mode] if action.key?(:mouse_mode)

          mouse_format = action[:mouse_format] if action.key?(:mouse_format)

          i = j + 1
        elsif processed[i] == "\n"
          cursor[:row] += 1
          cursor[:col] = 0
          i += 1
        elsif processed[i] == "\r"
          cursor[:col] = 0
          i += 1
        elsif processed[i] == "\t"
          cursor[:col] = ((cursor[:col] / 8) + 1) * 8
          cursor[:col] = cols - 1 if cursor[:col] >= cols
          i += 1
        elsif processed[i] == "\b"
          cursor[:col] -= 1 if cursor[:col].positive?
          i += 1
        elsif processed[i] == "\a"
          # Bell — ignore
          i += 1
        elsif processed[i] == "\x0e"
          active_charset = :g1
          i += 1
        elsif processed[i] == "\x0f"
          active_charset = :g0
          i += 1
        elsif processed[i] == "\e"
          # Handle non-CSI escape sequences
          if processed[i + 1] == "7"
            # DECSC — Save Cursor
            if use_alt_screen
              alt_saved_cursor = { row: cursor[:row], col: cursor[:col] }
              saved_cursor = alt_saved_cursor
            else
              normal_saved_cursor = { row: cursor[:row], col: cursor[:col] }
              saved_cursor = normal_saved_cursor
            end
            i += 2
          elsif processed[i + 1] == "8"
            # DECRC — Restore Cursor
            if saved_cursor
              cursor[:row] = saved_cursor[:row]
              cursor[:col] = saved_cursor[:col]
            end
            i += 2
          elsif processed[i + 1] == "(" && %w[0 B].include?(processed[i + 2])
            g0_charset = (processed[i + 2] == "0" ? :dec : :ascii)
            i += 3
          elsif processed[i + 1] == ")" && %w[0 B].include?(processed[i + 2])
            g1_charset = (processed[i + 2] == "0" ? :dec : :ascii)
            i += 3
          elsif processed[i + 1]&.match?(%r{[()*+\-./]})
            # Other ISO 2022 charset sequences (e.g. G2/G3 or other charsets)
            i += 3
          else
            i += 1
          end
        elsif (char, char_len = _utf8_char_at(processed, i))
          # Printable character (including multi-byte UTF-8)
          # cursor row/col are always clamped within bounds
          cell = grid[cursor[:row]][cursor[:col]]
          current_charset = (active_charset == :g1 ? g1_charset : g0_charset)
          mapped_char = char
          mapped_char = DEC_MAP[char] if current_charset == :dec && DEC_MAP.key?(char)
          cell[:char] = mapped_char
          cell.merge!(attrs)
          cursor[:col] += 1
          cursor[:col] = cols - 1 if cursor[:col] >= cols
          i += char_len
        else # rubocop:disable Lint/DuplicateBranch
          i += 1
        end

        # Handle scrolling within the defined scroll region
        region_top = scroll_region[:top]
        region_bottom = scroll_region[:bottom]

        next unless cursor[:row] > region_bottom

        scroll_lines = [cursor[:row] - region_bottom, rows].min
        # Shift lines within the scroll region up
        (region_top..(region_bottom - scroll_lines)).each do |ri|
          src = ri + scroll_lines
          grid[ri] = grid[src]
        end
        # Fill bottom of scroll region with blank lines
        ((region_bottom - scroll_lines + 1)..region_bottom).each do |ri|
          grid[ri] = Array.new(cols) { default_cell.dup }
        end
        cursor[:row] = region_bottom
      end

      {
        size: { rows: rows, cols: cols },
        cursor: {
          row: cursor[:row],
          col: cursor[:col],
          visible: cursor_visible,
          style: cursor_style,
        },
        rows: grid,
        pending_dsr: pending_dsr,
        cursor_visible: cursor_visible,
        cursor_style: cursor_style,
        mouse_mode: mouse_mode,
        mouse_format: mouse_format,
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/BlockNesting

    # Rebuild ANSI output from a state hash (for rendering/screenshot)
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def self.build_frame(state)
      rows = state.dig(:size, :rows) || state["size"]["rows"]
      state.dig(:size, :cols) || state["size"]["cols"]
      grid = state[:rows] || state["rows"]
      cursor = state[:cursor] || state["cursor"]
      mouse_mode = state[:mouse_mode] || state["mouse_mode"] || :none
      mouse_format = state[:mouse_format] || state["mouse_format"] || :normal

      out = +""
      out << "\e[0m"
      out << "\e[2J\e[H"

      grid.each_with_index do |row, ri|
        row.each_with_index do |cell, _ci|
          char = cell[:char] || cell["char"] || " "
          fg = cell[:fg] || cell["fg"] || "default"
          bg = cell[:bg] || cell["bg"] || "default"
          bold = cell[:bold] || cell["bold"] || false
          italic = cell[:italic] || cell["italic"] || false
          underline = cell[:underline] || cell["underline"] || false
          blink = cell[:blink] || cell["blink"] || false

          codes = []
          codes << "1" if bold
          codes << "3" if italic
          codes << "4" if underline
          codes << "5" if blink

          fg_code = _color_code(fg, "38")
          bg_code = _color_code(bg, "48")

          codes << fg_code if fg_code
          codes << bg_code if bg_code

          out << "\e[#{codes.join(";")}m" unless codes.empty?
          out << char
        end
        out << "\n" if ri < rows - 1
      end

      # Reconstruct cursor visibility
      cursor_vis = true
      cursor_vis = cursor[:visible] != false && cursor["visible"] != false if cursor.is_a?(Hash)
      out << (cursor_vis ? "\e[?25h" : "\e[?25l")

      # Reconstruct cursor style
      if cursor.is_a?(Hash)
        style = cursor[:style] || cursor["style"]
        out << "\e[#{style} q" if style
      end

      # Reconstruct mouse mode and format
      out << case mouse_mode
             when :normal
               "\e[?1000h"
             when :drag
               "\e[?1002h"
             when :all
               "\e[?1003h"
             else
               "\e[?1000l\e[?1002l\e[?1003l"
             end

      out << if mouse_format == :sgr
               "\e[?1006h"
             else
               "\e[?1006l"
             end

      out << "\e[0m"
      out
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
    def self._apply_csi(seq, cursor, attrs, grid, rows, cols, saved_cursor, scroll_region)
      # Strip leading escape char if present
      cleaned = seq.sub(/^\e/, "")
      match = cleaned.match(/^\[(\??)([\d;]*)( ?)([A-HJ-KP-SX@`fhlmnRrsuq])$/)
      return [false, nil, {}] unless match

      is_private = (match[1] == "?")
      params = match[2].split(";").map(&:to_i)
      match[3]
      command = match[4]

      new_saved = nil
      action = {}

      case command
      when "m"
        _apply_sgr(params, attrs)
      when "A" # CUU — Cursor Up
        n = params[0] || 1
        n = 1 if n.zero?
        cursor[:row] = [cursor[:row] - n, 0].max
      when "B" # CUD — Cursor Down
        n = params[0] || 1
        n = 1 if n.zero?
        cursor[:row] = [cursor[:row] + n, rows - 1].min
      when "C" # CUF — Cursor Forward
        n = params[0] || 1
        n = 1 if n.zero?
        cursor[:col] = [cursor[:col] + n, cols - 1].min
      when "D" # CUB — Cursor Back
        n = params[0] || 1
        n = 1 if n.zero?
        cursor[:col] = [cursor[:col] - n, 0].max
      when "H", "f" # CUP — Cursor Position
        r = (params[0] || 1) - 1
        c = (params[1] || 1) - 1
        cursor[:row] = r.clamp(0, rows - 1)
        cursor[:col] = c.clamp(0, cols - 1)
      when "J" # ED — Erase in Display
        case params[0]
        when nil, 0
          _erase_down(cursor, grid, rows, cols)
        when 1
          _erase_up(cursor, grid, cols)
        when 2, 3
          _erase_all(grid, rows, cols)
          cursor[:row] = 0
          cursor[:col] = 0
        end
      when "K" # EL — Erase in Line
        case params[0]
        when nil, 0
          _erase_line_right(cursor, grid, cols)
        when 1
          _erase_line_left(cursor, grid, cols)
        when 2
          _erase_line(cursor, grid, cols)
        end
      when "X" # Erase Characters
        n = params[0] || 1
        n.times do |i|
          next unless cursor[:row] < rows && cursor[:col] + i < cols

          grid[cursor[:row]][cursor[:col] + i][:char] = " "
        end
      when "s" # DECSC — Save Cursor (CSI variant)
        new_saved = { row: cursor[:row], col: cursor[:col] }
      when "u" # DECRC — Restore Cursor (CSI variant)
        if saved_cursor
          cursor[:row] = saved_cursor[:row]
          cursor[:col] = saved_cursor[:col]
        end
      when "r" # DECSTBM — Set Scroll Region
        top = (params[0] || 1) - 1
        bottom = (params[1] || rows) - 1
        top = top.clamp(0, rows - 1)
        bottom = bottom.clamp(0, rows - 1)
        if top < bottom
          scroll_region[:top] = top
          scroll_region[:bottom] = bottom
        else
          scroll_region[:top] = 0
          scroll_region[:bottom] = rows - 1
        end
        cursor[:row] = 0
        cursor[:col] = 0
      when "h"
        if is_private
          params.each do |p|
            case p
            when 47, 1047, 1049
              action[:alt_screen] = true
              action[:alt_screen_code] = p
            when 25
              action[:cursor_visible] = true
            when 1000
              action[:mouse_mode] = :normal
            when 1002
              action[:mouse_mode] = :drag
            when 1003
              action[:mouse_mode] = :all
            when 1006
              action[:mouse_format] = :sgr
            end
          end
        end
      when "l"
        if is_private
          params.each do |p|
            case p
            when 47, 1047, 1049
              action[:alt_screen] = false
              action[:alt_screen_code] = p
            when 25
              action[:cursor_visible] = false
            when 1000, 1002, 1003
              action[:mouse_mode] = :none
            when 1006
              action[:mouse_format] = :normal
            end
          end
        end
      when "q"
        style_val = params[0] || 0
        action[:cursor_style] = style_val
      when "n" # DSR — Device Status Report request
        return [params[0] == 6, nil, {}]
      when "R" # DSR response (from terminal side) or CPR — ignore
        nil
      end

      [false, new_saved, action]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def self._apply_sgr(params, attrs)
      if params.empty? || params == [0]
        return attrs.merge!(fg: "default", bg: "default", bold: false, italic: false, underline: false,
                            blink: false,)
      end

      i = 0
      while i < params.length
        p = params[i]
        case p
        when 0
          attrs.merge!(fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: false)
        when 1
          attrs[:bold] = true
        when 3
          attrs[:italic] = true
        when 4
          attrs[:underline] = true
        when 5, 6
          attrs[:blink] = true
        when 22
          attrs[:bold] = false
        when 23
          attrs[:italic] = false
        when 24
          attrs[:underline] = false
        when 25
          attrs[:blink] = false
        when 7, 27
          # Reverse — swap fg and bg
          attrs[:fg], attrs[:bg] = attrs[:bg], attrs[:fg]
        when 30..37
          attrs[:fg] = SGR_16_TO_NAME[p - 30] || "color#{p - 30}"
        when 38
          # Extended foreground
          if params[i + 1] == 5
            color = params[i + 2]
            attrs[:fg] = "color#{color}"
            i += 2
          # :nocov:
          elsif params[i + 1] == 2
            # :nocov:
            r = params[i + 2]
            g = params[i + 3]
            b = params[i + 4]
            attrs[:fg] = format("#%<r>02x%<g>02x%<b>02x", r: r, g: g, b: b)
            i += 4
          end
        when 39
          attrs[:fg] = "default"
        when 40..47
          attrs[:bg] = SGR_16_TO_NAME[p - 40] || "bg_color#{p - 40}"
        when 48
          # Extended background
          if params[i + 1] == 5
            color = params[i + 2]
            attrs[:bg] = "color#{color}"
            i += 2
          elsif params[i + 1] == 2
            r = params[i + 2]
            g = params[i + 3]
            b = params[i + 4]
            attrs[:bg] = format("#%<r>02x%<g>02x%<b>02x", r: r, g: g, b: b)
            i += 4
          end
        when 49
          attrs[:bg] = "default"
        when 90..97
          attrs[:fg] = "bright_#{SGR_16_TO_NAME[p - 90] || "color#{p - 90 + 8}"}"
        when 100..107
          attrs[:bg] = "bright_#{SGR_16_TO_NAME[p - 100] || "color#{p - 100 + 8}"}"
        end
        i += 1
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def self._erase_down(cursor, grid, rows, cols)
      r = cursor[:row]
      c = cursor[:col]

      # Erase from cursor to end of line
      (c...cols).each { |ci| _erase_cell(grid[r][ci]) if r < rows }

      # Erase remaining lines
      ((r + 1)...rows).each do |ri|
        cols.times { |ci| _erase_cell(grid[ri][ci]) }
      end
    end

    def self._erase_up(cursor, grid, cols)
      r = cursor[:row]
      c = cursor[:col]

      # Erase lines above cursor
      (0...r).each do |ri|
        cols.times { |ci| _erase_cell(grid[ri][ci]) }
      end

      # Erase from start of line to cursor
      (0..c).each { |ci| _erase_cell(grid[r][ci]) }
    end

    def self._erase_all(grid, rows, cols)
      rows.times do |ri|
        cols.times { |ci| _erase_cell(grid[ri][ci]) }
      end
    end

    def self._erase_cell(cell)
      cell.merge!(default_cell)
    end

    def self._erase_line_right(cursor, grid, cols)
      r = cursor[:row]
      c = cursor[:col]
      (c...cols).each { |ci| _erase_cell(grid[r][ci]) if r < grid.length }
    end

    def self._erase_line_left(cursor, grid, _cols)
      r = cursor[:row]
      c = cursor[:col]
      (0..c).each { |ci| _erase_cell(grid[r][ci]) if r < grid.length }
    end

    def self._erase_line(cursor, grid, cols)
      r = cursor[:row]
      cols.times { |ci| _erase_cell(grid[r][ci]) if r < grid.length }
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def self._color_code(name, prefix)
      case name
      when "default" then nil
      when /^#([0-9a-fA-F]{6})$/
        r = ::Regexp.last_match(1)[0..1].to_i(16)
        g = ::Regexp.last_match(1)[2..3].to_i(16)
        b = ::Regexp.last_match(1)[4..5].to_i(16)
        "#{prefix};2;#{r};#{g};#{b}"
      when /^(bright_)?(.+)$/
        base_name = ::Regexp.last_match(2)
        index = SGR_16_TO_NAME.key(base_name)
        index += 8 if ::Regexp.last_match(1) && index && index < 8
        index ? "#{prefix};5;#{index}" : nil
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def self.default_cell
      { char: " ", fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: false }
    end

    # Extract a single UTF-8 character at position i in a binary string.
    # Returns [char_string, byte_length] or nil if the byte is not printable/valid.
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
    def self._utf8_char_at(str, i)
      byte = str.getbyte(i)
      return nil unless byte

      if byte < 0x80
        # Single-byte ASCII
        return nil unless byte >= 0x20 # only printable, skip control chars

        return [byte.chr, 1]
      end

      # Multi-byte UTF-8
      len = if byte & 0xE0 == 0xC0
              2
            elsif byte & 0xF0 == 0xE0
              3
            elsif byte & 0xF8 == 0xF0
              4
            else
              return nil # continuation byte or invalid — let main loop advance
            end
      return nil if i + len > str.bytesize

      bytes = str.byteslice(i, len)
      char = bytes.dup.force_encoding("UTF-8")
      return nil unless char.valid_encoding?

      [char, len]
    # :nocov:
    rescue StandardError
      nil
      # :nocov:
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
  end
  # rubocop:enable Metrics/ModuleLength
end

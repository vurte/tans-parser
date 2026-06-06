# frozen_string_literal: true

require "spec_helper"

RSpec.describe TansParser::ANSIParser do
  describe ".parse" do
    it "handles plain text" do
      state = described_class.parse("hello world", 10, 40)
      expect(state[:rows][0][0..4].map { |c| c[:char] }.join).to eq("hello")
      expect(state[:cursor][:row]).to eq(0)
      expect(state[:cursor][:col]).to eq(11)
    end

    it "handles line feeds" do
      state = described_class.parse("hello\nworld", 10, 40)
      expect(state[:rows][0][0..4].map { |c| c[:char] }.join).to eq("hello")
      expect(state[:rows][1][0..4].map { |c| c[:char] }.join).to eq("world")
    end

    it "handles carriage returns" do
      state = described_class.parse("hello\rworld", 10, 40)
      expect(state[:rows][0][0..4].map { |c| c[:char] }.join).to eq("world")
    end

    it "handles SGR color codes" do
      state = described_class.parse("\e[31mred\e[0mnormal", 10, 40)
      expect(state[:rows][0][0][:fg]).to eq("red")
      expect(state[:rows][0][0][:char]).to eq("r")
      expect(state[:rows][0][3][:fg]).to eq("default")
    end

    it "handles bold" do
      state = described_class.parse("\e[1mbold text\e[0m", 10, 40)
      expect(state[:rows][0][0][:bold]).to be true
      expect(state[:rows][0][5][:bold]).to be true
    end

    it "handles cursor movements" do
      state = described_class.parse("AB\e[2DC", 10, 40)
      # 1. Write A at (0,0), B at (0,1)
      # 2. Cursor back 2 → (0,0)
      # 3. Write C at (0,0) → overwrites A
      expect(state[:rows][0][0][:char]).to eq("C")
      expect(state[:rows][0][1][:char]).to eq("B")
    end

    it "handles erasing in display" do
      state = described_class.parse("first_line\nsecond_line\e[2Jnew", 10, 40)
      # After erase entire display, only "new" should remain visible
      expect(state[:rows][0][0..2].map { |c| c[:char] }.join).to eq("new")
    end

    it "handles ANSI 256-color codes" do
      state = described_class.parse("\e[38;5;82mgreenish\e[0m", 10, 40)
      expect(state[:rows][0][0][:fg]).to eq("color82")
    end

    it "handles ANSI truecolor codes" do
      state = described_class.parse("\e[38;2;255;100;50mcustom\e[0m", 10, 40)
      expect(state[:rows][0][0][:fg]).to eq("#ff6432")
    end

    it "handles scrolling overflow" do
      # Fill more lines than the screen height
      state = described_class.parse((1..15).map { |i| "line_#{i}" }.join("\n"), 10, 40)
      # Only the last 10 lines should be visible
      text = state[:rows].map { |r| r.map { |c| c[:char] }.join.strip }.reject(&:empty?)
      expect(text.first).to eq("line_6")
      expect(text.last).to eq("line_15")
    end

    it "handles cursor jump to large row safely" do
      # CUP to row 200 in a 10-row terminal — should clamp without error
      state = described_class.parse("\e[200;1Hcontent", 10, 40)
      expect(state[:cursor][:row]).to eq(9)
      expect(state[:rows].length).to eq(10)
      expect(state[:rows][9].map { |c| c[:char] }.join).to start_with("content")
    end

    it "scrolls efficiently with many newlines" do
      # 100 newlines in a 10-row terminal — should not error
      input = "first\n#{"\n" * 100}last"
      state = described_class.parse(input, 10, 40)
      expect(state[:rows].length).to eq(10)
      line = state[:rows][9].map { |c| c[:char] }.join
      expect(line).to include("last")
    end

    it "handles tabs" do
      state = described_class.parse("a\tb", 10, 40)
      expect(state[:rows][0][0][:char]).to eq("a")
      expect(state[:rows][0][8][:char]).to eq("b")
    end

    it "skips ISO 2022 charset sequences like \e(B" do
      state = described_class.parse("\e(Bhello\e(B world", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to start_with("hello world")
    end

    it "detects DSR (Device Status Report) request" do
      state = described_class.parse("\e[6n", 10, 40)
      expect(state[:pending_dsr]).to be true
    end

    it "sets pending_dsr to false when no DSR request" do
      state = described_class.parse("hello world", 10, 40)
      expect(state[:pending_dsr]).to be false
    end

    it "skips DEC private mode set sequences like \\e[?25h" do
      # Cursor visibility toggle should not leak chars into output
      state = described_class.parse("hello\e[?25hworld", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to start_with("helloworld")
    end

    it "skips DEC private mode reset sequences like \\e[?25l" do
      state = described_class.parse("before\e[?25lafter", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to start_with("beforeafter")
    end

    it "supports alternate screen buffer switching \\e[?1049h" do
      state = described_class.parse("vim\e[?1049hcontent", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to start_with("content")
    end

    it "restores normal screen buffer on \\e[?1049l" do
      state = described_class.parse("main\e[?1049halt\e[?1049lrestored", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to start_with("mainrestored")
    end

    # ---- Cursor movement ----

    it "handles CUU (cursor up)" do
      state = described_class.parse("line1\nline2\e[AX", 10, 40)
      # After writing line1, newline, line2: cursor at row 1, col 5
      # CUU 1: cursor moves to row 0, col 5; X overwrites position 5
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "handles CUD (cursor down)" do
      state = described_class.parse("\e[2BX", 10, 40)
      # Cursor down 2 from row 0 → row 2
      expect(state[:rows][2][0][:char]).to eq("X")
    end

    it "handles CUF (cursor forward)" do
      state = described_class.parse("A\e[2CB", 10, 40)
      expect(state[:rows][0][0][:char]).to eq("A")
      # After A at col 0, CUF 2 moves cursor to col 3
      expect(state[:rows][0][3][:char]).to eq("B")
    end

    it "handles backspace" do
      state = described_class.parse("AB\bC", 10, 40)
      expect(state[:rows][0][0][:char]).to eq("A")
      expect(state[:rows][0][1][:char]).to eq("C")
    end

    # ---- SGR variants ----

    it "handles SGR background color" do
      state = described_class.parse("\e[41mbg red\e[0m", 10, 40)
      expect(state[:rows][0][0][:bg]).to eq("red")
    end

    it "handles SGR bright foreground" do
      state = described_class.parse("\e[91mbright red\e[0m", 10, 40)
      expect(state[:rows][0][0][:fg]).to eq("bright_red")
    end

    it "handles SGR bright background" do
      state = described_class.parse("\e[101mbg bright red\e[0m", 10, 40)
      expect(state[:rows][0][0][:bg]).to eq("bright_red")
    end

    it "handles SGR normal (22) turning off bold" do
      state = described_class.parse("\e[1mbold\e[22m normal", 10, 40)
      expect(state[:rows][0][0][:bold]).to be true
      # Characters after \e[22m should not be bold
      expect(state[:rows][0][5][:bold]).to be false
    end

    it "handles SGR normal (23) turning off italic" do
      state = described_class.parse("\e[3mitalic\e[23m normal", 10, 40)
      expect(state[:rows][0][0][:italic]).to be true
      expect(state[:rows][0][7][:italic]).to be false
    end

    it "handles SGR normal (24) turning off underline" do
      state = described_class.parse("\e[4mul\e[24m normal", 10, 40)
      expect(state[:rows][0][0][:underline]).to be true
      expect(state[:rows][0][3][:underline]).to be false
    end

    it "handles SGR reverse video (7)" do
      state = described_class.parse("\e[31;44m\e[7mrev\e[0m", 10, 40)
      # After reverse, fg and bg are swapped
      expect(state[:rows][0][0][:fg]).to eq("blue")
      expect(state[:rows][0][0][:bg]).to eq("red")
    end

    it "handles SGR blink (5) as no-op" do
      state = described_class.parse("\e[5mblink\e[0m", 10, 40)
      expect(state[:rows][0][0][:char]).to eq("b")
    end

    # ---- Erase variants ----

    it "handles ED erase-down (0)" do
      state = described_class.parse("AAAA\nBBBB\nCCCC\e[H\e[0J", 10, 40)
      # Move cursor to home (0,0) with CUP, then erase down
      # Erases from cursor to end of screen
      expect(state[:rows][0][0][:char]).to eq(" ")
      expect(state[:rows][1][0][:char]).to eq(" ")
      expect(state[:rows][2][0][:char]).to eq(" ")
    end

    it "handles ED erase-up (1)" do
      state = described_class.parse("AAAA\nBBBB\e[2A\e[1J", 10, 40)
      # Move to row 0 (CUU 2 from row 2), then erase from start to cursor
      expect(state[:rows][0][0][:char]).to eq(" ")
      expect(state[:rows][1][0][:char]).to eq("B")
    end

    it "handles EL erase-right (0)" do
      state = described_class.parse("ABCD\e[2D\e[0K", 10, 40)
      # Cursor back 2 to position 2 ('C'), erase to end of line
      expect(state[:rows][0][0][:char]).to eq("A")
      expect(state[:rows][0][1][:char]).to eq("B")
      expect(state[:rows][0][2][:char]).to eq(" ")
    end

    it "handles EL erase-left (1)" do
      state = described_class.parse("ABCD\e[1K", 10, 40)
      # Erase from start to cursor (col 4)
      expect(state[:rows][0][0][:char]).to eq(" ")
    end

    it "handles EL erase-line (2)" do
      state = described_class.parse("ABCD\e[2K", 10, 40)
      expect(state[:rows][0][0][:char]).to eq(" ")
    end

    it "handles Erase Characters (X)" do
      state = described_class.parse("ABCD\e[2D\e[2X", 10, 40)
      # Cursor back 2 to 'C', erase 2 chars
      expect(state[:rows][0][0][:char]).to eq("A")
      expect(state[:rows][0][1][:char]).to eq("B")
      expect(state[:rows][0][2][:char]).to eq(" ")
      expect(state[:rows][0][3][:char]).to eq(" ")
    end

    it "erase operations reset all cell attributes, not just char" do
      raw = "\e[48;5;236mHello\e[0m\e[2K"
      state = described_class.parse(raw, 10, 40)

      cell = state[:rows][0][0]
      expect(cell[:char]).to eq(" ")
      expect(cell[:bg]).to eq("default")
      expect(cell[:fg]).to eq("default")
      expect(cell[:bold]).to be false
      expect(cell[:italic]).to be false
      expect(cell[:underline]).to be false
      expect(cell[:blink]).to be false
    end

    it "erase-right after colored text resets background" do
      raw = "\e[48;5;236m#{"X" * 20}\e[0m\e[10D\e[0K"
      state = described_class.parse(raw, 10, 40)

      # cells before column 10: X with bg=color236
      expect(state[:rows][0][0][:char]).to eq("X")
      expect(state[:rows][0][0][:bg]).to eq("color236")

      # cells from column 10: erased, all attributes default
      expect(state[:rows][0][10][:char]).to eq(" ")
      expect(state[:rows][0][10][:bg]).to eq("default")
      expect(state[:rows][0][10][:fg]).to eq("default")
    end

    # ---- Multi-byte UTF-8 ----

    it "handles multi-byte UTF-8 characters" do
      state = described_class.parse("café", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("café")
    end

    it "handles emoji characters" do
      state = described_class.parse("hello 🌍", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("hello 🌍")
    end

    it "assigns width 2 to CJK characters" do
      state = described_class.parse("漢字", 1, 10)
      expect(state[:rows][0][0][:width]).to eq(2)
      expect(state[:rows][0][1][:char]).to eq("")
      expect(state[:rows][0][1][:width]).to eq(0)
    end

    it "assigns width 2 to emoji and clears continuation cell" do
      state = described_class.parse("🔥X", 1, 10)
      expect(state[:rows][0][0][:width]).to eq(2)
      expect(state[:rows][0][1][:char]).to eq("")
      expect(state[:rows][0][1][:width]).to eq(0)
      expect(state[:rows][0][2][:char]).to eq("X")
    end

    it "handles emoji at start of string followed by ASCII" do
      state = described_class.parse("🔥hello", 1, 15)
      line = state[:rows][0].map { |c| c[:char] }.join
      expect(line).to include("🔥hello")
    end

    it "appends combining character to previous cell" do
      state = described_class.parse("café", 1, 10) # e + combining acute accent (width 0)
      # The combining accent should be appended to cell 3 (the "e")
      expect(state[:rows][0][3][:char]).to eq("é")
      expect(state[:rows][0][4][:char]).to eq(" ") # no new cell created
    end

    # ---- DECSC / DECRC (Save / Restore Cursor) ----

    it "saves and restores cursor via ESC 7 / ESC 8" do
      state = described_class.parse("hello\e7world\e8X", 10, 40)
      # After "hello": cursor at (0,5)
      # ESC 7: save (0,5)
      # "world": cursor at (0,10)
      # ESC 8: restore to (0,5)
      # X overwrites position 5
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "saves and restores cursor via CSI s / CSI u" do
      state = described_class.parse("hello\e[sworld\e[uX", 10, 40)
      # After "hello": cursor at (0,5)
      # CSI s: save (0,5)
      # "world": cursor at (0,10)
      # CSI u: restore to (0,5)
      # X overwrites position 5
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "restore without prior save is a no-op" do
      state = described_class.parse("hello\e8X", 10, 40)
      # ESC 8 without prior save: cursor unchanged, X writes at next position
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    # ---- DECSTBM (Set Scroll Region) ----

    it "scrolls within a defined scroll region" do
      # Fill content, then set scroll region to rows 4-7 (1-indexed)
      # Write more content to trigger scroll within the region
      input = (1..10).map { |i| "line#{i}" }.join("\n")
      input += "\e[4;7r"  # scroll region rows 4-7
      input += "\e[7;1H"  # move cursor to row 7
      input += "\nextra1\nextra2"
      state = described_class.parse(input, 10, 40)
      # Rows 0-2 (lines 1-3) should be unchanged
      expect(state[:rows][0].map { |c| c[:char] }.join.strip).to eq("line1")
      expect(state[:rows][1].map { |c| c[:char] }.join.strip).to eq("line2")
      expect(state[:rows][2].map { |c| c[:char] }.join.strip).to eq("line3")
      # Row 9 should still be line10 (outside scroll region)
      expect(state[:rows][9].map { |c| c[:char] }.join.strip).to eq("line10")
    end

    it "resets scroll region with \\e[r" do
      state = described_class.parse("line1\nline2\n\e[1;2r\e[r", 10, 40)
      # \e[1;2r sets scroll region to rows 1-2
      # \e[r resets to full screen
      expect(state[:cursor][:row]).to eq(0)
      expect(state[:cursor][:col]).to eq(0)
    end
  end

  describe ".build_frame" do
    it "reconstructs ANSI from empty state" do
      state = described_class.parse("", 3, 10)
      frame = described_class.build_frame(state)
      expect(frame).to start_with("\e[0m")
      expect(frame).to end_with("\e[0m")
    end

    it "round-trips plain text" do
      original = described_class.parse("hello world", 5, 40)
      frame = described_class.build_frame(original)
      round_tripped = described_class.parse(frame, 5, 40)
      expect(round_tripped[:rows][0].map { |c| c[:char] }.join.strip).to eq("hello world")
    end

    it "round-trips styled text" do
      original = described_class.parse("\e[31mred\e[1mbold red\e[0m normal", 5, 40)
      frame = described_class.build_frame(original)
      round_tripped = described_class.parse(frame, 5, 40)
      # Color names are converted to numeric codes by build_frame, so round-trip
      # produces color1 (256-color index for red) instead of "red"
      expect(round_tripped[:rows][0][0][:fg]).to eq("color1")
      expect(round_tripped[:rows][0][0][:char]).to eq("r")
    end

    it "build_frame handles string keys" do
      state = {
        "size" => { "rows" => 2, "cols" => 5 },
        "cursor" => { "row" => 0, "col" => 0 },
        "rows" => [
          [{ "char" => "S", "fg" => "green", "bg" => "default", "bold" => false, "italic" => false,
             "underline" => false, }],
          [],
        ],
      }
      frame = described_class.build_frame(state)
      # green → 256-color index 2
      expect(frame).to include("38;5;2")
    end
  end

  describe "._color_code" do
    it "returns 256-color sequence for named ANSI colors" do
      code = described_class._color_code("red", "38")
      expect(code).to eq("38;5;1")
    end

    it "returns 256-color sequence for bright colors" do
      code = described_class._color_code("bright_red", "38")
      expect(code).to eq("38;5;9")
    end

    it "returns TrueColor sequence for hex colors" do
      code = described_class._color_code("#ff8800", "48")
      expect(code).to eq("48;2;255;136;0")
    end

    it "returns nil for default" do
      expect(described_class._color_code("default", "38")).to be_nil
    end
  end

  describe "advanced ANSI features" do
    it "parses SGR blink sequences" do
      state = described_class.parse("normal \e[5mblinking\e[25m normal_again", 5, 40)
      row = state[:rows][0]
      expect(row[0][:blink]).to be false
      expect(row[7][:blink]).to be true
      expect(row[15][:blink]).to be false
    end

    it "handles cursor visibility sequences" do
      state1 = described_class.parse("\e[?25l", 5, 40)
      expect(state1[:cursor_visible]).to be false
      expect(state1[:cursor][:visible]).to be false

      state2 = described_class.parse("\e[?25h", 5, 40)
      expect(state2[:cursor_visible]).to be true
      expect(state2[:cursor][:visible]).to be true
    end

    it "handles DECSCUSR cursor shape sequences" do
      state = described_class.parse("\e[4 q", 5, 40) # Underline
      expect(state[:cursor_style]).to eq(4)
      expect(state[:cursor][:style]).to eq(4)
    end

    it "separates alternate screen and normal screen buffers" do
      # 1. Switch to alt screen (1047h), write something, then switch back (1047l)
      state = described_class.parse("normal\e[?1047halt\e[?1047lnormal2", 5, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("normalnormal2")

      # 2. Stays in alt screen buffer
      state_alt = described_class.parse("normal\e[?1047halt", 5, 40)
      line_alt = state_alt[:rows][0].map { |c| c[:char] }.join.strip
      expect(line_alt).to eq("alt")
    end

    it "supports DEC Special Character and Line Drawing mapping via ISO-2022" do
      # G0 set to DEC: \e(0. 'q' -> '─', 'x' -> '│'.
      state1 = described_class.parse("\e(0qx\e(Bqx", 5, 40)
      line1 = state1[:rows][0][0..3].map { |c| c[:char] }.join
      expect(line1).to eq("─│qx")

      # G1 set to DEC: \e)0, switched via Shift Out \x0e and Shift In \x0f
      state2 = described_class.parse("\e)0abc\x0eqx\x0fext", 5, 40)
      line2 = state2[:rows][0][0..7].map { |c| c[:char] }.join
      expect(line2).to eq("abc─│ext")
    end

    it "parses mouse tracking mode and format sequences" do
      state1 = described_class.parse("\e[?1000h\e[?1006h", 5, 40)
      expect(state1[:mouse_mode]).to eq(:normal)
      expect(state1[:mouse_format]).to eq(:sgr)

      state2 = described_class.parse("\e[?1002h", 5, 40)
      expect(state2[:mouse_mode]).to eq(:drag)
      expect(state2[:mouse_format]).to eq(:normal) # default

      state3 = described_class.parse("\e[?1003h", 5, 40)
      expect(state3[:mouse_mode]).to eq(:all)

      state4 = described_class.parse("\e[?1002h\e[?1002l", 5, 40)
      expect(state4[:mouse_mode]).to eq(:none)
    end

    it "reconstructs mouse tracking and cursor parameters in build_frame" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: { row: 0, col: 0, visible: false, style: 2 },
        mouse_mode: :all,
        mouse_format: :sgr,
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?25l")
      expect(frame).to include("\e[2 q")
      expect(frame).to include("\e[?1003h")
      expect(frame).to include("\e[?1006h")
    end

    it "reconstructs mouse mode :normal" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: { row: 0, col: 0 },
        mouse_mode: :normal,
        mouse_format: :normal,
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?1000h")
    end

    it "reconstructs mouse mode :drag" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: { row: 0, col: 0 },
        mouse_mode: :drag,
        mouse_format: :normal,
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?1002h")
    end

    it "reconstructs mouse mode :none" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: { row: 0, col: 0 },
        mouse_mode: :none,
        mouse_format: :normal,
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?1000l")
      expect(frame).to include("\e[?1002l")
      expect(frame).to include("\e[?1003l")
    end
  end

  describe "edge case coverage" do
    it "handles CRLF line endings" do
      state = described_class.parse("hello\r\nworld", 10, 40)
      line0 = state[:rows][0].map { |c| c[:char] }.join.strip
      line1 = state[:rows][1].map { |c| c[:char] }.join.strip
      expect(line0).to eq("hello")
      expect(line1).to eq("world")
    end

    it "ignores bell character" do
      state = described_class.parse("hel\alo", 10, 40)
      # "hel" + BEL + "lo" → bell is skipped → "hello"
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("hello")
    end

    it "handles SGR 39 resetting foreground to default" do
      state = described_class.parse("\e[31mred\e[39mdefault", 10, 40)
      expect(state[:rows][0][0][:fg]).to eq("red")
      expect(state[:rows][0][3][:fg]).to eq("default")
    end

    it "handles SGR 49 resetting background to default" do
      state = described_class.parse("\e[41mbg_red\e[49mdefault", 10, 40)
      expect(state[:rows][0][0][:bg]).to eq("red")
      expect(state[:rows][0][6][:bg]).to eq("default")
    end

    it "handles SGR 0 within compound sequence" do
      state = described_class.parse("\e[1;31;0;44mtext", 10, 40)
      cell = state[:rows][0][0]
      # SGR 0 resets bold and fg, then 44 sets bg to blue
      expect(cell[:fg]).to eq("default")
      expect(cell[:bg]).to eq("blue")
      expect(cell[:bold]).to be false
    end

    it "handles 24-bit background color (48;2;r;g;b)" do
      state = described_class.parse("\e[48;2;100;200;50mbg24\e[0m", 10, 40)
      expect(state[:rows][0][0][:bg]).to eq("#64c832")
    end

    it "resets scroll region when top >= bottom" do
      state = described_class.parse("\e[5;4r", 10, 40)
      # top=4, bottom=3 → reset to full terminal
      expect(state[:cursor][:row]).to eq(0)
      expect(state[:cursor][:col]).to eq(0)
    end

    it "erases lines above cursor with ED 1 from non-zero row" do
      state = described_class.parse("AAAA\nBBBB\nCCCC\n\e[1J", 10, 40)
      # Cursor at (3,0), ED 1 erases rows 0-2 and start of row 3
      expect(state[:rows][0][0][:char]).to eq(" ")
      expect(state[:rows][1][0][:char]).to eq(" ")
      expect(state[:rows][2][0][:char]).to eq(" ")
    end

    it "skips other ISO 2022 G2/G3 sequences (\e*, \e+, \e-)" do
      state = described_class.parse("\e*0hello\e+0world", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("helloworld")
    end

    it "saves and restores cursor in alt screen via CSI s/u" do
      state = described_class.parse("\e[?1047hhello\e[smore\e[uX", 10, 40)
      # "hello" at (0,0)-(0,4), save cursor at (0,5), "more" at (0,5)-(0,8),
      # restore to (0,5), X overwrites position 5
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "saves and restores cursor in alt screen via ESC 7/8" do
      state = described_class.parse("\e[?1047hhello\e7more\e8X", 10, 40)
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "handles backspace at column zero" do
      state = described_class.parse("\bX", 10, 40)
      # Backspace at col 0 is a no-op, X writes at col 0
      expect(state[:rows][0][0][:char]).to eq("X")
    end

    it "skips unrecognized C0 control characters" do
      raw = "hel\x01lo"
      raw = raw.dup.force_encoding("ASCII-8BIT") if raw.encoding != Encoding::ASCII_8BIT
      state = described_class.parse(raw, 10, 40)
      # "hel" + SOH + "lo" → SOH skipped → "hello"
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("hello")
    end

    it "handles 3-byte UTF-8 characters" do
      state = described_class.parse("price: €", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("price: €")
    end

    it "handles invalid UTF-8 continuation bytes gracefully" do
      raw = "hi".b + "\x80".b + "there".b
      state = described_class.parse(raw, 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("hithere")
    end

    it "handles CSI cursor up with zero n" do
      state = described_class.parse("hello\nX\e[0AB", 10, 40)
      # CUU with n=0 defaults to n=1, moves up from (1,1) to (0,1)
      expect(state[:rows][0][1][:char]).to eq("B")
    end

    it "handles ISO 2022 G2 designator \e. and G3 designator \e/" do
      state = described_class.parse("\e.A\e/Btext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles ESC followed by unrecognized char" do
      state = described_class.parse("a\eZtext", 10, 40)
      # ESC consumed by else branch, Z is printed as printable
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("aZtext")
    end

    it "handles ED with mode 3 (full erase)" do
      state = described_class.parse("AAAA\nBBBB\n\e[3J", 10, 40)
      # Mode 3 is like mode 2: erase all, cursor to home
      expect(state[:rows][0][0][:char]).to eq(" ")
      expect(state[:rows][1][0][:char]).to eq(" ")
      expect(state[:cursor][:row]).to eq(0)
      expect(state[:cursor][:col]).to eq(0)
    end

    it "handles ED and EL with explicit nil/0 params" do
      # ED with explicit 0: erase down from cursor
      state1 = described_class.parse("AAAA\nBBBB\nCCCC\e[0J", 10, 40)
      # Cursor at (2,4), ED 0 erases from cursor (2,4) through end
      expect(state1[:rows][0][0][:char]).to eq("A")
      expect(state1[:rows][2][4][:char]).to eq(" ")

      # EL with explicit 0: erase right from cursor
      state2 = described_class.parse("ABCD\e[0K", 10, 40)
      # Cursor at (0,4), erase right erases col 4+
      expect(state2[:rows][0][0][:char]).to eq("A")
      expect(state2[:rows][0][3][:char]).to eq("D")
    end

    it "handles EL erase-line with explicit 2" do
      state = described_class.parse("ABCD\e[2K", 10, 40)
      expect(state[:rows][0][0][:char]).to eq(" ")
    end

    it "applies cursor style action" do
      state = described_class.parse("\e[3 q", 10, 40)
      expect(state[:cursor][:style]).to eq(3)
      expect(state[:cursor_style]).to eq(3)
    end

    it "handles DECSTBM with default params (\e[r)" do
      state = described_class.parse("\e[r", 10, 40)
      expect(state[:cursor][:row]).to eq(0)
      expect(state[:cursor][:col]).to eq(0)
    end

    it "handles CUF and CUB with zero n" do
      state = described_class.parse("A\e[0C\e[0DB", 10, 40)
      expect(state[:rows][0][1][:char]).to eq("B")
    end

    it "handles Erase Characters with cursor at edge" do
      state = described_class.parse("\e[3X", 10, 5)
      expect(state[:rows][0][0][:char]).to eq(" ")
    end

    it "handles DSR response (\e[R) as no-op" do
      state = described_class.parse("text\e[10;20Rmore", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("textmore")
    end

    it "handles non-private h/l sequences as no-ops" do
      state = described_class.parse("\e[1h\e[2ltext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles SGR italic off via 23" do
      state = described_class.parse("\e[3mitalic\e[23mnormal", 10, 40)
      expect(state[:rows][0][0][:italic]).to be true
      expect(state[:rows][0][7][:italic]).to be false
    end

    it "handles SGR underline off via 24" do
      state = described_class.parse("\e[4mul\e[24mnormal", 10, 40)
      expect(state[:rows][0][0][:underline]).to be true
      expect(state[:rows][0][3][:underline]).to be false
    end

    it "handles SGR blink off via 25" do
      state = described_class.parse("\e[5mblink\e[25mnormal", 10, 40)
      expect(state[:rows][0][0][:blink]).to be true
      expect(state[:rows][0][6][:blink]).to be false
    end

    it "handles SGR bold off via 22" do
      state = described_class.parse("\e[1mbold\e[22mnormal", 10, 40)
      expect(state[:rows][0][0][:bold]).to be true
      expect(state[:rows][0][5][:bold]).to be false
    end

    it "handles ESC CSI sequence without params" do
      state = described_class.parse("\e[J", 10, 40)
      # ED with no params = erase down from cursor (0,0) = erase entire display area
      expect(state[:rows][0][0][:char]).to eq(" ")
    end

    it "handles multi-codepoint emoji (4-byte UTF-8)" do
      state = described_class.parse("emoji 🎉", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("emoji 🎉")
    end

    it "handles cursor at far right edge with printable char" do
      state = described_class.parse("X", 5, 1)
      # Cursor at col 0, write X → col becomes 1, clamped to 0
      # Actually col is 0, writes X, col becomes 1, col >= cols (1 >= 1),
      # so col = cols - 1 = 0
      expect(state[:rows][0][0][:char]).to eq("X")
    end

    it "handles newline within scroll region" do
      state = described_class.parse("a\nb\nc\nd\ne\nf", 3, 10)
      # 3 rows, 6 lines → last 3 visible
      text_rows = state[:rows].map { |r| r.map { |c| c[:char] }.join.strip }.reject(&:empty?)
      expect(text_rows).to eq(%w[d e f])
    end

    it "handles tab expansion at edge" do
      state = described_class.parse("a\tb", 10, 40)
      # tab from col 1: (((1 / 8) + 1) * 8) = 8
      expect(state[:rows][0][8][:char]).to eq("b")
    end

    it "handles tab at far right edge" do
      # Fill 39 chars then tab in a 40-col terminal
      input = "#{"X" * 39}\tY"
      state = described_class.parse(input, 10, 40)
      expect(state[:rows][0][39][:char]).to eq("Y")
    end

    it "handles unhandled CSI commands as no-ops" do
      state = described_class.parse("a\e[Eb\e[Fc\e[Gd", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("abcd")
    end

    it "handles CSI with unhandled command letter (P and S)" do
      state = described_class.parse("ab\e[Pcd", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("abcd")
    end

    it "handles malformed CSI sequence" do
      state = described_class.parse("a\e[Tb", 10, 40)
      # T is not in the CSI command regex, so regex doesn't match
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to include("a")
    end

    it "handles double alt screen switch" do
      state = described_class.parse("\e[?1047h\e[?1047hcontent", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("content")
    end

    it "handles ESC at end of string" do
      state = described_class.parse("abc\e", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("abc")
    end

    it "handles G1 charset set to ASCII via ESC )B" do
      state = described_class.parse("\e)0abc\x0edec\x0f\e)Babc\x0echars\x0f", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to include("abc")
    end

    it "sets G0 charset to ASCII via ESC (B" do
      state = described_class.parse("\e(Btext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles newline at bottom of scroll region" do
      # Fill the terminal completely and then add more content
      input = (1..12).map { |i| "line#{i}" }.join("\n")
      state = described_class.parse(input, 10, 40)
      expect(state[:rows].length).to eq(10)
    end
  end

  describe ".build_frame edge cases" do
    it "builds frame with italic cell" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: [
          [{ char: "I", fg: "default", bg: "default", bold: false, italic: true, underline: false, blink: false }],
          [],
        ],
        cursor: { row: 0, col: 0 },
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[3m")
    end

    it "builds frame with underline cell" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: [
          [{ char: "U", fg: "default", bg: "default", bold: false, italic: false, underline: true, blink: false }],
          [],
        ],
        cursor: { row: 0, col: 0 },
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[4m")
    end

    it "builds frame with blink cell" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: [
          [{ char: "B", fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: true }],
          [],
        ],
        cursor: { row: 0, col: 0 },
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[5m")
    end

    it "builds frame with background color cell" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: [
          [{ char: "C", fg: "default", bg: "red", bold: false, italic: false, underline: false, blink: false }],
          [],
        ],
        cursor: { row: 0, col: 0 },
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("48;5;1")
    end

    it "builds frame with cursor not visible" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: { row: 0, col: 0, visible: false },
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?25l")
    end

    it "builds frame with nil cursor" do
      state_data = {
        size: { rows: 2, cols: 5 },
        rows: Array.new(2) { Array.new(5) { described_class.default_cell.dup } },
        cursor: nil,
      }
      frame = described_class.build_frame(state_data)
      expect(frame).to include("\e[?25h")
    end
  end

  describe "._color_code edge cases" do
    it "returns nil for unknown color name" do
      code = described_class._color_code("unknown_color_xyz", "38")
      expect(code).to be_nil
    end

    it "returns nil for unknown bright color name" do
      code = described_class._color_code("bright_unknown", "48")
      expect(code).to be_nil
    end
  end

  describe "._utf8_char_at edge cases" do
    it "returns nil at end of string" do
      result = described_class._utf8_char_at("ab", 2)
      expect(result).to be_nil
    end
  end

  describe "._apply_sgr edge cases" do
    it "handles invalid SGR code as no-op" do
      state = described_class.parse("\e[999mtext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles invalid extended background color sub-parameter" do
      state = described_class.parse("\e[48;3;0mtext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles Erase Characters beyond right edge" do
      # n=10 Erase Characters in a 5-col terminal: cols 0-4 erased, 5-9 skipped
      state = described_class.parse("\e[10X", 10, 5)
      expect(state[:rows][0][0][:char]).to eq(" ")
      expect(state[:rows][0][4][:char]).to eq(" ")
    end
  end

  describe "._utf8_char_at direct tests" do
    it "handles ASCII character" do
      result = described_class._utf8_char_at("abc", 0)
      expect(result).to eq(["a", 1])
    end

    it "returns nil for C0 control character" do
      raw = "\x01".b
      result = described_class._utf8_char_at(raw, 0)
      expect(result).to be_nil
    end

    it "returns nil for invalid multi-byte sequence" do
      raw = "\xF0\x80\x80\x80".b
      result = described_class._utf8_char_at(raw, 0)
      expect(result).to be_nil
    end

    it "returns nil when i+len exceeds bytesize" do
      # 4-byte start (0xF0) but only 3 bytes available
      raw = "\xF0\x80\x80".b
      result = described_class._utf8_char_at(raw, 0)
      expect(result).to be_nil
    end
  end

  describe "._apply_csi edge cases" do
    it "handles CUD with zero n" do
      state = described_class.parse("\e[0B", 10, 40)
      expect(state[:cursor][:row]).to eq(1)
    end

    it "handles CSI restore cursor without prior save" do
      state = described_class.parse("hello\e[uX", 10, 40)
      expect(state[:rows][0][5][:char]).to eq("X")
    end

    it "handles ED with invalid mode" do
      state = described_class.parse("AAAA\n\e[5J", 10, 40)
      # Mode 5 is not handled — no-op
      expect(state[:rows][0][0][:char]).to eq("A")
    end

    it "handles EL with invalid mode" do
      state = described_class.parse("AAAA\e[3K", 10, 40)
      # Mode 3 is not handled — no-op
      expect(state[:rows][0][0][:char]).to eq("A")
    end

    it "handles unhandled private mode set" do
      state = described_class.parse("\e[?1h\e[?999htext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end

    it "handles unhandled private mode reset" do
      state = described_class.parse("\e[?1l\e[?999ltext", 10, 40)
      line = state[:rows][0].map { |c| c[:char] }.join.strip
      expect(line).to eq("text")
    end
  end

  describe "._color_code with nil" do
    it "returns nil for nil color name" do
      expect(described_class._color_code(nil, "38")).to be_nil
    end
  end

  describe "erase methods with out-of-bounds cursor" do
    it "_erase_down handles row out of bounds safely" do
      grid = Array.new(3) { Array.new(5) { described_class.default_cell.dup } }
      grid[0][0][:char] = "X"
      described_class._erase_down({ row: 10, col: 0 }, grid, 3, 5)
      expect(grid[0][0][:char]).to eq("X")
    end

    it "_erase_line_right handles row out of bounds safely" do
      grid = Array.new(3) { Array.new(5) { described_class.default_cell.dup } }
      grid[0][0][:char] = "X"
      described_class._erase_line_right({ row: 10, col: 0 }, grid, 5)
      expect(grid[0][0][:char]).to eq("X")
    end

    it "_erase_line_left handles row out of bounds safely" do
      grid = Array.new(3) { Array.new(5) { described_class.default_cell.dup } }
      grid[2][0][:char] = "Z"
      described_class._erase_line_left({ row: 10, col: 0 }, grid, 5)
      expect(grid[2][0][:char]).to eq("Z")
    end

    it "_erase_line handles row out of bounds safely" do
      grid = Array.new(3) { Array.new(5) { described_class.default_cell.dup } }
      grid[0][0][:char] = "X"
      described_class._erase_line({ row: 10, col: 0 }, grid, 5)
      expect(grid[0][0][:char]).to eq("X")
    end
  end
end

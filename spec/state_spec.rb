# frozen_string_literal: true

require "spec_helper"

RSpec.describe TansParser::State do
  describe ".new" do
    it "raises ArgumentError when :size key is missing" do
      expect { described_class.new(rows: []) }.to raise_error(ArgumentError, /:size/)
    end

    it "raises ArgumentError when :rows key is missing" do
      expect { described_class.new(size: { rows: 5, cols: 10 }) }.to raise_error(ArgumentError, /:rows/)
    end

    it "creates a valid state with correct data" do
      data = { size: { rows: 2, cols: 10 },
               rows: [[{ char: "X", fg: "default", bg: "default", bold: false, italic: false,
                         underline: false, }]],
               cursor: { row: 0, col: 0 }, }
      state = described_class.new(data)
      expect(state.rows).to eq(2)
      expect(state.cols).to eq(10)
    end
  end

  def make_grid(rows, cols, content = nil)
    Array.new(rows) do |ri|
      Array.new(cols) do |ci|
        {
          char: content ? content[ri]&.[](ci) || " " : " ",
          fg: "default",
          bg: "default",
          bold: false,
          italic: false,
          underline: false,
        }
      end
    end
  end

  def make_state(rows: 5, cols: 20, grid: nil, cursor: nil)
    data = {
      size: { rows: rows, cols: cols },
      cursor: cursor || { row: 0, col: 0 },
      rows: grid || make_grid(rows, cols),
    }
    described_class.new(data)
  end

  describe "#plain_text" do
    it "returns plain text without ANSI" do
      grid = make_grid(2, 5)
      grid[0][0][:char] = "H"
      grid[0][1][:char] = "i"
      grid[1][0][:char] = "o"
      state = make_state(rows: 2, cols: 5, grid: grid)
      expect(state.plain_text).to eq("Hi\no")
    end

    it "strips trailing whitespace" do
      grid = make_grid(2, 5)
      grid[0][0][:char] = "A"
      state = make_state(rows: 2, cols: 5, grid: grid)
      expect(state.plain_text).to eq("A\n")
    end
  end

  describe "#text_at" do
    it "returns text at a specific position" do
      grid = make_grid(2, 10)
      "Hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      state = make_state(rows: 2, cols: 10, grid: grid)
      expect(state.text_at(0, 0, 5)).to eq("Hello")
    end

    it "returns empty string for out-of-bounds" do
      state = make_state(rows: 2, cols: 5)
      expect(state.text_at(10, 10)).to eq("")
    end
  end

  describe "#foreground_at / #background_at / #style_at" do
    it "returns cell colors and styles" do
      grid = make_grid(2, 5)
      grid[0][0][:fg] = "cyan"
      grid[0][0][:bg] = "bright_black"
      grid[0][0][:bold] = true
      state = make_state(rows: 2, cols: 5, grid: grid)
      expect(state.foreground_at(0, 0)).to eq("cyan")
      expect(state.background_at(0, 0)).to eq("bright_black")
      expect(state.style_at(0, 0)).to eq({ bold: true, italic: false, underline: false })
    end
  end

  describe "#to_ai_json" do
    it "includes size, cursor, text, highlights, summary" do
      state = make_state(rows: 3, cols: 10)
      result = state.to_ai_json
      expect(result.keys).to contain_exactly(:size, :cursor, :text, :highlights, :summary)
      expect(result[:size]).to eq({ rows: 3, cols: 10 })
      expect(result[:cursor]).to eq({ row: 0, col: 0 })
    end

    it "empty terminal has no highlights" do
      state = make_state(rows: 3, cols: 10)
      result = state.to_ai_json
      expect(result[:highlights]).to be_empty
      expect(result[:text]).to eq("\n\n")
    end

    it "captures per-line foreground colors" do
      grid = make_grid(3, 10)
      "cyan text".chars.each_with_index do |c, i|
        grid[0][i][:char] = c
        grid[0][i][:fg] = "cyan"
      end
      state = make_state(rows: 3, cols: 10, grid: grid)
      result = state.to_ai_json
      expect(result[:highlights].size).to eq(1)
      expect(result[:highlights][0][:fg]).to eq("cyan")
      expect(result[:highlights][0][:text]).to eq("cyan text ")
    end

    it "captures bold, italic, underline" do
      grid = make_grid(1, 3)
      grid[0][0][:char] = "B"
      grid[0][0][:bold] = true
      grid[0][1][:char] = "I"
      grid[0][1][:italic] = true
      grid[0][2][:char] = "U"
      grid[0][2][:underline] = true
      state = make_state(rows: 1, cols: 3, grid: grid)
      result = state.to_ai_json
      hl = result[:highlights][0]
      expect(hl[:bold]).to be true
      expect(hl[:italic]).to be true
      expect(hl[:underline]).to be true
    end

    it "collects multiple foregrounds as array" do
      grid = make_grid(1, 5)
      grid[0][0][:char] = "R"
      grid[0][0][:fg] = "red"
      grid[0][1][:char] = "G"
      grid[0][1][:fg] = "green"
      state = make_state(rows: 1, cols: 5, grid: grid)
      result = state.to_ai_json
      hl = result[:highlights][0]
      expect(hl[:fg]).to contain_exactly("red", "green")
    end

    it "captures background color" do
      grid = make_grid(1, 3)
      grid[0][1][:char] = "X"
      grid[0][1][:bg] = "blue"
      state = make_state(rows: 1, cols: 3, grid: grid)
      result = state.to_ai_json
      expect(result[:highlights][0][:bg]).to eq("blue")
    end

    it "handles TrueColor hex format" do
      grid = make_grid(1, 3)
      grid[0][0][:char] = "T"
      grid[0][0][:fg] = "#ff8800"
      state = make_state(rows: 1, cols: 3, grid: grid)
      result = state.to_ai_json
      expect(result[:highlights][0][:fg]).to eq("#ff8800")
    end

    it "handles 256-color format" do
      grid = make_grid(1, 3)
      grid[0][0][:char] = "C"
      grid[0][0][:fg] = "color82"
      state = make_state(rows: 1, cols: 3, grid: grid)
      result = state.to_ai_json
      expect(result[:highlights][0][:fg]).to eq("color82")
    end

    it "does not highlight rows with only default colors" do
      grid = make_grid(3, 5)
      grid[0][0][:char] = "n"
      grid[0][1][:char] = "o"
      grid[0][2][:char] = "p"
      grid[0][3][:char] = "e"
      state = make_state(rows: 3, cols: 5, grid: grid)
      result = state.to_ai_json
      expect(result[:highlights]).to be_empty
    end

    it "summary mentions cursor and styled rows" do
      grid = make_grid(3, 10)
      grid[0][0][:char] = "S"
      grid[0][0][:fg] = "red"
      grid[0][0][:bold] = true
      state = make_state(rows: 3, cols: 10, grid: grid, cursor: { row: 2, col: 5 })
      result = state.to_ai_json
      expect(result[:summary]).to include("[2,5]")
      expect(result[:summary]).to include("1 styled row")
      expect(result[:summary]).to include("red")
    end

    it "summary lists distinct colors" do
      grid = make_grid(2, 5)
      grid[0][0][:char] = "A"
      grid[0][0][:fg] = "cyan"
      grid[1][0][:char] = "B"
      grid[1][0][:fg] = "cyan"
      state = make_state(rows: 2, cols: 5, grid: grid)
      result = state.to_ai_json
      expect(result[:summary]).to include("cyan")
    end

    it "pluralizes 'styled rows' for multiple rows" do
      grid = make_grid(3, 5)
      grid[0][0][:char] = "A"
      grid[0][0][:fg] = "red"
      grid[1][0][:char] = "B"
      grid[1][0][:bold] = true
      state = make_state(rows: 3, cols: 5, grid: grid)
      result = state.to_ai_json
      expect(result[:summary]).to include("2 styled rows")
    end

    it "handles non-Hash cursor gracefully" do
      data = {
        size: { rows: 2, cols: 5 },
        cursor: "invalid",
        rows: make_grid(2, 5),
      }
      state = described_class.new(data)
      result = state.to_ai_json
      expect(result[:cursor]).to eq({})
      expect(result[:summary]).to include("[0,0]")
    end
  end

  describe "#find_text" do
    it "finds text occurrences" do
      grid = make_grid(2, 15)
      "Hello World".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      grid[1][0][:char] = "H"
      state = make_state(rows: 2, cols: 15, grid: grid)
      results = state.find_text("Hello")
      expect(results.size).to eq(1)
      expect(results.first[:row]).to eq(0)
      expect(results.first[:col]).to eq(0)
    end

    it "finds multiple occurrences on the same row" do
      grid = make_grid(1, 20)
      "aXbXc".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      state = make_state(rows: 1, cols: 20, grid: grid)
      results = state.find_text("X")
      expect(results.size).to eq(2)
      expect(results[0][:col]).to eq(1)
      expect(results[1][:col]).to eq(3)
    end

    it "returns empty array when no match" do
      grid = make_grid(1, 10)
      "hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      state = make_state(rows: 1, cols: 10, grid: grid)
      expect(state.find_text("MISSING")).to eq([])
    end

    it "finds text with Regexp pattern" do
      grid = make_grid(1, 20)
      "abc 123 def".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      state = make_state(rows: 1, cols: 20, grid: grid)
      results = state.find_text(/\d{3}/)
      expect(results.size).to eq(1)
      expect(results[0][:col]).to eq(4)
      expect(results[0][:full_line]).to include("abc 123 def")
      expect(results[0][:text]).to eq("123")
    end

    it "does not hang on ReDoS pattern" do
      grid = make_grid(1, 100)
      "#{"a" * 50}!".chars.each_with_index { |c, i| grid[0][i][:char] = c }
      state = make_state(rows: 1, cols: 100, grid: grid)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      results = state.find_text(/(a+)+b/)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      expect(elapsed).to be < 10
      expect(results).to be_an(Array)
    end

    describe "match: :exact" do
      it "finds an exact row match" do
        grid = make_grid(2, 15)
        "Hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 2, cols: 15, grid: grid)
        results = state.find_text("Hello", match: :exact)
        expect(results.size).to eq(1)
        expect(results.first[:row]).to eq(0)
        expect(results.first[:col]).to eq(0)
        expect(results.first[:text]).to eq("Hello")
      end

      it "ignores trailing whitespace in exact match" do
        grid = make_grid(1, 15)
        "Hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        # rest of cells are spaces (default)
        state = make_state(rows: 1, cols: 15, grid: grid)
        results = state.find_text("Hello", match: :exact)
        expect(results.size).to eq(1)
      end

      it "returns empty when no exact match" do
        grid = make_grid(2, 15)
        "Hello World".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 2, cols: 15, grid: grid)
        expect(state.find_text("Hello", match: :exact)).to eq([])
      end

      it "finds exact match with Regexp argument" do
        grid = make_grid(1, 15)
        "Hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 15, grid: grid)
        results = state.find_text(/Hello/, match: :exact)
        expect(results.size).to eq(1)
      end
    end

    describe "match: :regex" do
      it "compiles a string to Regexp and finds matches" do
        grid = make_grid(1, 20)
        "abc 123 def 456".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 20, grid: grid)
        results = state.find_text("\\d{3}", match: :regex)
        expect(results.size).to eq(2)
        expect(results[0][:text]).to eq("123")
        expect(results[1][:text]).to eq("456")
      end

      it "accepts a Regexp directly in regex mode" do
        grid = make_grid(1, 20)
        "abc 123 def".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 20, grid: grid)
        results = state.find_text(/\d{3}/, match: :regex)
        expect(results.size).to eq(1)
        expect(results[0][:text]).to eq("123")
      end

      it "returns empty array when no regex match" do
        grid = make_grid(1, 10)
        "hello".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 10, grid: grid)
        expect(state.find_text("\\d+", match: :regex)).to eq([])
      end
    end

    describe "match: :partial (explicit)" do
      it "works the same as default for String patterns" do
        grid = make_grid(1, 20)
        "hello world".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 20, grid: grid)
        results = state.find_text("world", match: :partial)
        expect(results.size).to eq(1)
        expect(results[0][:col]).to eq(6)
      end

      it "captures matched substring for Regexp patterns" do
        grid = make_grid(1, 20)
        "abc 42 def".chars.each_with_index { |c, i| grid[0][i][:char] = c }
        state = make_state(rows: 1, cols: 20, grid: grid)
        results = state.find_text(/\d{2}/, match: :partial)
        expect(results.size).to eq(1)
        expect(results[0][:text]).to eq("42")
      end
    end

    describe "unknown match mode" do
      it "raises ArgumentError" do
        state = make_state(rows: 1, cols: 10)
        expect { state.find_text("x", match: :fuzzy) }.to raise_error(ArgumentError, /unknown match mode/)
      end
    end
  end

  describe "#foreground_at / #background_at / #style_at edge cases" do
    it "returns nil for out-of-bounds color queries" do
      state = make_state(rows: 2, cols: 5)
      expect(state.foreground_at(10, 10)).to be_nil
      expect(state.background_at(10, 10)).to be_nil
      expect(state.style_at(10, 10)).to be_nil
    end
  end

  describe "cursor and mouse attributes" do
    it "exposes cursor and mouse parameters correctly" do
      data = {
        size: { rows: 2, cols: 5 },
        rows: make_grid(2, 5),
        cursor: { row: 0, col: 0, visible: false, style: 3 },
        mouse_mode: :drag,
        mouse_format: :sgr,
      }
      state = described_class.new(data)
      expect(state.cursor_visible).to be false
      expect(state.cursor_style).to eq(3)
      expect(state.mouse_mode).to eq(:drag)
      expect(state.mouse_format).to eq(:sgr)
    end

    it "uses explicit cursor_visible key when provided" do
      data = {
        size: { rows: 2, cols: 5 },
        rows: make_grid(2, 5),
        cursor: { row: 0, col: 0, visible: false },
        cursor_visible: true,
      }
      state = described_class.new(data)
      expect(state.cursor_visible).to be true
    end

    it "uses explicit cursor_style key when provided" do
      data = {
        size: { rows: 2, cols: 5 },
        rows: make_grid(2, 5),
        cursor: { row: 0, col: 0, style: 3 },
        cursor_style: 5,
      }
      state = described_class.new(data)
      expect(state.cursor_style).to eq(5)
    end
  end

  describe "#to_ai_json background highlights" do
    it "collects multiple background colors as array" do
      grid = make_grid(1, 5)
      grid[0][0][:char] = "R"
      grid[0][0][:bg] = "red"
      grid[0][1][:char] = "G"
      grid[0][1][:bg] = "green"
      state = make_state(rows: 1, cols: 5, grid: grid)
      result = state.to_ai_json
      hl = result[:highlights][0]
      expect(hl[:bg]).to contain_exactly("red", "green")
    end

    it "handles default cursor style fallback" do
      data = {
        size: { rows: 2, cols: 5 },
        rows: make_grid(2, 5),
        cursor: { row: 0, col: 0 },
      }
      state = described_class.new(data)
      expect(state.cursor_style).to eq(1)
    end
  end

  describe "#annotate_role" do
    it "adds an annotation to the state" do
      state = make_state(rows: 5, cols: 30)
      state.annotate_role(:dialog, row: 1, col: 2, width: 20, height: 5, text: "My Dialog")
      expect(state.annotations.size).to eq(1)
      expect(state.annotations.first[:role]).to eq(:dialog)
      expect(state.annotations.first[:row]).to eq(1)
    end

    it "accepts extra keyword arguments" do
      state = make_state(rows: 5, cols: 30)
      state.annotate_role(:button, row: 0, col: 0, width: 4, height: 1, fg: "red", checked: true)
      ann = state.annotations.first
      expect(ann[:fg]).to eq("red")
      expect(ann[:checked]).to be true
    end

    it "initializes with annotations from data hash" do
      data = {
        size: { rows: 2, cols: 10 },
        rows: make_grid(2, 10),
        cursor: { row: 0, col: 0 },
        annotations: [{ role: :statusbar, row: 1, col: 0, width: 10, height: 1 }],
      }
      state = described_class.new(data)
      expect(state.annotations.size).to eq(1)
      expect(state.annotations.first[:role]).to eq(:statusbar)
    end
  end

  describe "#diff" do
    it "returns empty array for identical states" do
      state_a = make_state(rows: 3, cols: 10)
      state_b = make_state(rows: 3, cols: 10)
      expect(state_a.diff(state_b)).to eq([])
    end

    it "detects a changed character" do
      grid_a = make_grid(2, 5)
      grid_a[0][2][:char] = "A"
      grid_b = make_grid(2, 5)
      grid_b[0][2][:char] = "B"
      state_a = make_state(rows: 2, cols: 5, grid: grid_a)
      state_b = make_state(rows: 2, cols: 5, grid: grid_b)
      diff = state_a.diff(state_b)
      expect(diff.size).to eq(1)
      expect(diff.first[:row]).to eq(0)
      expect(diff.first[:col]).to eq(2)
      expect(diff.first[:before][:char]).to eq("A")
      expect(diff.first[:after][:char]).to eq("B")
    end

    it "with chars_only: true ignores color changes" do
      grid_a = make_grid(2, 5)
      grid_a[0][0][:char] = "X"
      grid_a[0][0][:fg] = "red"
      grid_b = make_grid(2, 5)
      grid_b[0][0][:char] = "X"
      grid_b[0][0][:fg] = "blue"
      state_a = make_state(rows: 2, cols: 5, grid: grid_a)
      state_b = make_state(rows: 2, cols: 5, grid: grid_b)
      expect(state_a.diff(state_b, chars_only: true)).to eq([])
    end

    it "with chars_only: false reports color changes" do
      grid_a = make_grid(2, 5)
      grid_a[0][0][:char] = "X"
      grid_a[0][0][:fg] = "red"
      grid_b = make_grid(2, 5)
      grid_b[0][0][:char] = "X"
      grid_b[0][0][:fg] = "blue"
      state_a = make_state(rows: 2, cols: 5, grid: grid_a)
      state_b = make_state(rows: 2, cols: 5, grid: grid_b)
      expect(state_a.diff(state_b).size).to eq(1)
    end

    it "handles different grid sizes" do
      state_a = make_state(rows: 2, cols: 5)
      state_b = make_state(rows: 3, cols: 5)
      expect(state_a.diff(state_b)).not_to be_empty
    end

    it "accepts a raw hash as other_state" do
      state_a = make_state(rows: 2, cols: 5)
      data = { size: { rows: 2, cols: 5 }, cursor: { row: 0, col: 0 }, rows: make_grid(2, 5) }
      expect(state_a.diff(data)).to eq([])
    end

    it "with ignore_rows: skips specified rows" do
      grid_a = make_grid(3, 5)
      grid_a[0][2][:char] = "A"
      grid_a[2][2][:char] = "B"
      grid_b = make_grid(3, 5)
      grid_b[0][2][:char] = "X"
      grid_b[2][2][:char] = "Y"
      state_a = make_state(rows: 3, cols: 5, grid: grid_a)
      state_b = make_state(rows: 3, cols: 5, grid: grid_b)
      diff = state_a.diff(state_b, ignore_rows: [0])
      expect(diff.size).to eq(1)
      expect(diff.first[:row]).to eq(2)
    end

    it "with ignore_rows: accepts empty array" do
      grid_a = make_grid(2, 5)
      grid_a[0][0][:char] = "X"
      grid_b = make_grid(2, 5)
      grid_b[0][0][:char] = "Y"
      state_a = make_state(rows: 2, cols: 5, grid: grid_a)
      state_b = make_state(rows: 2, cols: 5, grid: grid_b)
      diff = state_a.diff(state_b, ignore_rows: [])
      expect(diff.size).to eq(1)
    end
  end
end

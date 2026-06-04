# frozen_string_literal: true

require "spec_helper"

# rubocop:disable Metrics/ParameterLists

RSpec.describe TansParser::ScopedSelector do
  def make_grid(rows, cols)
    Array.new(rows) do
      Array.new(cols) do
        { char: " ", fg: "default", bg: "default", bold: false, italic: false, underline: false }
      end
    end
  end

  def make_state(grid: nil, rows: 5, cols: 30)
    TansParser::State.new(
      size: { rows: rows, cols: cols },
      cursor: { row: 0, col: 0 },
      rows: grid || make_grid(rows, cols),
    )
  end

  def write_text(grid, row, col, text, fg: "default", bg: "default", bold: false, underline: false)
    text.chars.each_with_index do |c, i|
      grid[row][col + i] = { char: c, fg: fg, bg: bg, bold: bold, italic: false, underline: underline }
    end
  end

  def write_line(grid, row, text, **)
    write_text(grid, row, 0, text, **)
  end

  def build_dialog(grid, start_row, start_col, width, height, content_lines)
    top = "┌#{"─" * (width - 2)}┐"
    bottom = "└#{"─" * (width - 2)}┘"
    write_text(grid, start_row, start_col, top)
    content_lines.each_with_index do |line, i|
      inner = line.ljust(width - 2)
      write_text(grid, start_row + 1 + i, start_col, "│#{inner}│")
    end
    write_text(grid, start_row + height - 1, start_col, bottom)
  end

  describe "#get_by_role" do
    it "only returns elements within the scoped element's bounds" do
      grid = make_grid(10, 40)
      # Button inside dialog
      write_text(grid, 3, 12, "[ OK ]")
      # Button outside dialog
      write_text(grid, 0, 0, "(Cancel)")
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.get_by_role(:button)
      expect(results.size).to eq(1)
      expect(results.first.text).to eq("OK")
    end
  end

  describe "#get_by_text" do
    it "only returns elements within the scoped element's bounds" do
      grid = make_grid(10, 40)
      write_text(grid, 3, 12, "[ Save ]")
      write_text(grid, 0, 0, "[ Save ]")
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.get_by_text("Save")
      expect(results.size).to eq(1)
    end
  end

  describe "#find_text" do
    it "only finds text within the scoped region" do
      grid = make_grid(8, 30)
      write_text(grid, 2, 12, "Hello")
      write_text(grid, 5, 0, "Hello")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text("Hello")
      expect(results.size).to eq(1)
      expect(results.first[:row]).to eq(2)
    end

    it "returns absolute grid coordinates" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "OK")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text("OK")
      expect(results.size).to eq(1)
      expect(results.first[:row]).to eq(3)
      expect(results.first[:col]).to eq(12)
    end

    it "supports exact match mode" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "OK")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text("OK", match: :exact)
      expect(results.size).to eq(1)
    end

    it "supports regex match mode" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "abc 42")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text("\\d{2}", match: :regex)
      expect(results.size).to eq(1)
      expect(results.first[:text]).to eq("42")
    end
  end

  describe "convenience methods" do
    it "returns scoped buttons" do
      grid = make_grid(10, 40)
      write_text(grid, 3, 12, "[ OK ]")
      write_text(grid, 0, 0, "(Cancel)")
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      expect(scoped.buttons.size).to eq(1)
      expect(scoped.button.text).to eq("OK")
    end

    it "returns nil for singular when no match" do
      grid = make_grid(10, 40)
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      expect(scoped.button).to be_nil
    end
  end

  describe "Selector#within" do
    it "yields a ScopedSelector when given a block" do
      grid = make_grid(10, 40)
      write_text(grid, 3, 12, "[ OK ]")
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)
      selector = TansParser::Selector.new(state)

      result = nil
      selector.within(dialog) do |scope|
        result = scope.get_by_role(:button)
      end
      expect(result.size).to eq(1)
      expect(result.first.text).to eq("OK")
    end

    it "supports partial mode with Regexp object" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "abc 42")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text(/\d{2}/)
      expect(results.size).to eq(1)
      expect(results.first[:text]).to eq("42")
    end

    it "supports exact mode with Regexp object" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "OK")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text(/OK/, match: :exact)
      expect(results.size).to eq(1)
    end

    it "returns empty when exact mode does not match" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "Hello")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text("Nope", match: :exact)
      expect(results).to eq([])
    end

    it "supports regex mode with Regexp object" do
      grid = make_grid(8, 30)
      write_text(grid, 3, 12, "abc 42")
      state = make_state(grid: grid, rows: 8, cols: 30)
      dialog = TansParser::Element.new(role: :dialog, row: 2, col: 10, width: 15, height: 4)

      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      results = scoped.find_text(/\d{2}/, match: :regex)
      expect(results.size).to eq(1)
      expect(results.first[:text]).to eq("42")
    end

    it "raises ArgumentError for unknown match mode" do
      grid = make_grid(5, 20)
      state = make_state(grid: grid, rows: 5, cols: 20)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 2, width: 10, height: 3)
      scoped = described_class.new(TansParser::Selector.new(state), dialog)
      expect { scoped.find_text("x", match: :fuzzy) }.to raise_error(ArgumentError, /unknown match mode/)
    end

    it "returns a ScopedSelector without a block" do
      grid = make_grid(10, 40)
      state = make_state(grid: grid, rows: 10, cols: 40)
      dialog = TansParser::Element.new(role: :dialog, row: 1, col: 10, width: 20, height: 5)
      selector = TansParser::Selector.new(state)

      scoped = selector.within(dialog)
      expect(scoped).to be_a(described_class)
    end
  end
end
# rubocop:enable Metrics/ParameterLists

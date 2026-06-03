# frozen_string_literal: true

require "spec_helper"

# rubocop:disable Metrics/ParameterLists

RSpec.describe TansParser::Selector do
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

  def write_text(grid, row, col, text, fg: "default", bg: "default", bold: false)
    text.chars.each_with_index do |c, i|
      grid[row][col + i] = { char: c, fg: fg, bg: bg, bold: bold, italic: false, underline: false }
    end
  end

  def write_line(grid, row, text, **)
    write_text(grid, row, 0, text, **)
  end

  describe "#get_by_role(:button)" do
    it "detects [ OK ] as a button" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      buttons = selector.buttons
      expect(buttons.size).to eq(1)
      expect(buttons.first.role).to eq(:button)
      expect(buttons.first.text).to eq("OK")
      expect(buttons.first.row).to eq(1)
    end

    it "detects (Cancel) as a button" do
      grid = make_grid(3, 20)
      write_line(grid, 0, "(Cancel)")
      selector = described_class.new(make_state(grid: grid))
      buttons = selector.buttons
      expect(buttons.size).to eq(1)
      expect(buttons.first.text).to eq("Cancel")
    end

    it "detects <Submit> as a button" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "<Submit>")
      selector = described_class.new(make_state(grid: grid))
      buttons = selector.buttons
      expect(buttons.size).to eq(1)
      expect(buttons.first.text).to eq("Submit")
    end

    it "detects multiple buttons on the same line" do
      grid = make_grid(3, 30)
      write_line(grid, 1, "[ OK ]  (Cancel)")
      selector = described_class.new(make_state(grid: grid))
      buttons = selector.buttons
      expect(buttons.size).to eq(2)
      expect(buttons.map(&:text)).to contain_exactly("OK", "Cancel")
    end

    it "does not detect empty brackets as buttons" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[] ()")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.buttons).to be_empty
    end

    it "captures foreground and background colors for buttons" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[Red]", fg: "red", bg: "blue")
      selector = described_class.new(make_state(grid: grid))
      button = selector.buttons.first
      expect(button.fg).to eq("red")
      expect(button.bg).to eq("blue")
    end
  end

  describe "#get_by_role(:checkbox)" do
    it "detects [x] as a checked checkbox" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[x] Enable logging")
      selector = described_class.new(make_state(grid: grid))
      checkboxes = selector.checkboxes
      expect(checkboxes.size).to eq(1)
      expect(checkboxes.first.text).to eq("Enable logging")
      expect(checkboxes.first.checked).to be true
    end

    it "detects [ ] as an unchecked checkbox" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[ ] Enable logging")
      selector = described_class.new(make_state(grid: grid))
      checkboxes = selector.checkboxes
      expect(checkboxes.size).to eq(1)
      expect(checkboxes.first.checked).to be false
    end

    it "detects [*] as a checked checkbox" do
      grid = make_grid(5, 30)
      write_line(grid, 3, "[*] Auto-save")
      selector = described_class.new(make_state(grid: grid))
      checkboxes = selector.checkboxes
      expect(checkboxes.size).to eq(1)
      expect(checkboxes.first.checked).to be true
    end

    it "detects [X] as a checked checkbox" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[X] Option")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.checkboxes.first.checked).to be true
    end

    it "detects multiple checkboxes" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[x] Option A")
      write_line(grid, 2, "[ ] Option B")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.checkboxes.size).to eq(2)
    end
  end

  describe "#get_by_role(:dialog)" do
    it "detects a simple box-drawing dialog" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│  Hello   │")
      write_line(grid, 3, "└──────────┘")
      selector = described_class.new(make_state(grid: grid))
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
      expect(dialogs.first.role).to eq(:dialog)
      expect(dialogs.first.text).to include("Hello")
      expect(dialogs.first.width).to eq(12)
      expect(dialogs.first.height).to eq(3)
    end

    it "returns empty when no dialog is present" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "plain text")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs).to be_empty
    end

    it "returns empty for incomplete dialog (no bottom border)" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│  Hello   │")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs).to be_empty
    end

    it "skips top-left corner character without matching top-right corner" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌── hello")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs).to be_empty
    end

    it "skips box with bottom-left but invalid bottom-right corner" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│  Hello   │")
      write_line(grid, 3, "└──────────X")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs).to be_empty
    end

    it "handles empty lines inside dialog" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│          │")
      write_line(grid, 3, "└──────────┘")
      selector = described_class.new(make_state(grid: grid))
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
    end
  end

  describe "#get_by_role(:statusbar)" do
    it "detects a bottom row with inverse colors" do
      grid = make_grid(5, 20)
      write_line(grid, 0, "Main content")
      write_line(grid, 4, " Ctrl+X Exit  ", bg: "blue")
      state = make_state(grid: grid)
      selector = described_class.new(state)
      bars = selector.statusbars
      expect(bars.size).to eq(1)
      expect(bars.first.role).to eq(:statusbar)
      expect(bars.first.text).to include("Ctrl+X Exit")
    end

    it "does not detect statusbar if bottom row has default bg" do
      grid = make_grid(5, 20)
      write_line(grid, 4, "normal text")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars).to be_empty
    end

    it "does not detect statusbar if bottom row has too few colored cells" do
      grid = make_grid(5, 20)
      write_line(grid, 4, "AB", bg: "blue")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars).to be_empty
    end

    it "does not detect statusbar on empty grid" do
      grid = make_grid(0, 20)
      selector = described_class.new(make_state(grid: grid, rows: 0))
      expect(selector.statusbars).to be_empty
    end

    it "does not detect statusbar with only whitespace text" do
      grid = make_grid(5, 20)
      write_line(grid, 4, "     ", bg: "blue")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars).to be_empty
    end
  end

  describe "#get_by_role(:progress)" do
    it "detects a progress bar" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[#####     ] 50%")
      selector = described_class.new(make_state(grid: grid))
      bars = selector.progress_bars
      expect(bars.size).to eq(1)
      expect(bars.first.role).to eq(:progress)
      expect(bars.first.text).to include("%")
    end

    it "detects progress bar with = signs" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[====>     ]")
      selector = described_class.new(make_state(grid: grid))
      bars = selector.progress_bars
      expect(bars.size).to eq(1)
      expect(bars.first.role).to eq(:progress)
    end

    it "detects progress bar with - signs" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[----      ]")
      selector = described_class.new(make_state(grid: grid))
      bars = selector.progress_bars
      expect(bars.size).to eq(1)
    end

    it "marks 100% as checked" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[##########]")
      selector = described_class.new(make_state(grid: grid))
      bars = selector.progress_bars
      expect(bars.size).to eq(1)
      expect(bars.first.checked).to be true
      expect(bars.first.text).to eq("100%")
    end
  end

  describe "#get_by_text" do
    it "finds elements by visible text" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[ OK ]")
      write_line(grid, 2, "hello world")
      selector = described_class.new(make_state(grid: grid))
      results = selector.get_by_text("OK")
      expect(results.size).to eq(1)
      expect(results.first.role).to eq(:button)
    end

    it "returns empty array when no text matches" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.get_by_text("Nope")).to eq([])
    end

    it "handles elements with nil text gracefully" do
      grid = make_grid(3, 20)
      sel = described_class.allocate
      sel.instance_variable_set(:@state, make_state(grid: grid))
      sel.instance_variable_set(:@elements, [TansParser::Element.new(role: :button)])
      expect(sel.get_by_text("anything")).to eq([])
    end
  end

  describe "#get_by_role" do
    it "accepts string role names" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      results = selector.get_by_role("button")
      expect(results.size).to eq(1)
    end

    it "returns empty for unknown role" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.get_by_role(:unknown)).to eq([])
    end
  end

  describe ".new" do
    it "accepts a raw hash and wraps it in State" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      data = {
        size: { rows: 3, cols: 20 },
        cursor: { row: 0, col: 0 },
        rows: grid,
      }
      selector = described_class.new(data)
      expect(selector.buttons.size).to eq(1)
    end
  end

  describe "#to_h" do
    it "excludes nil values" do
      el = TansParser::Element.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      hash = el.to_h
      expect(hash).to include(:role, :text, :row, :col, :width, :height)
      expect(hash).not_to have_key(:checked)
    end

    it "includes checked when true" do
      el = TansParser::Element.new(role: :checkbox, text: "Opt", row: 0, col: 0, width: 3, height: 1, checked: true)
      expect(el.to_h).to have_key(:checked)
    end

    it "includes focused when true" do
      el = TansParser::Element.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, focused: true)
      expect(el.to_h).to have_key(:focused)
    end

    it "includes fg and bg when set" do
      el = TansParser::Element.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, fg: "red", bg: "blue",
      )
      hash = el.to_h
      expect(hash[:fg]).to eq("red")
      expect(hash[:bg]).to eq("blue")
    end
  end
end
# rubocop:enable Metrics/ParameterLists

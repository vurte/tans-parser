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

  def write_text(grid, row, col, text, fg: "default", bg: "default", bold: false, underline: false)
    text.chars.each_with_index do |c, i|
      grid[row][col + i] = { char: c, fg: fg, bg: bg, bold: bold, italic: false, underline: underline }
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

    it "detects rounded-corner dialog with ╭╮╰╯" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "╭──────────╮")
      write_line(grid, 2, "│  Hello   │")
      write_line(grid, 3, "╰──────────╯")
      selector = described_class.new(make_state(grid: grid))
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
      expect(dialogs.first.text).to include("Hello")
    end

    it "detects double-line dialog with ╔╗╚╝" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "╔══════════╗")
      write_line(grid, 2, "║  Hello   ║")
      write_line(grid, 3, "╚══════════╝")
      selector = described_class.new(make_state(grid: grid))
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
      expect(dialogs.first.text).to include("Hello")
      expect(dialogs.first.width).to eq(12)
    end

    it "detects dialog with text in the top border" do
      grid = make_grid(5, 40)
      write_line(grid, 1, "╭─ Commands ────────────────────╮")
      write_line(grid, 2, "│ 1/1                           │")
      write_line(grid, 3, "│  /tools  List available tools │")
      write_line(grid, 4, "╰───────────────────────────────╯")
      selector = described_class.new(make_state(grid: grid, rows: 6, cols: 40))
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
      expect(dialogs.first.text).to include("tools")
    end

    it "skips too-narrow top border (tr_idx < 2)" do
      grid = make_grid(3, 10)
      write_line(grid, 1, "┌┐") # width 2, no content
      write_line(grid, 2, "└┘")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs).to be_empty
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

    it "detects statusbar on second-to-last row" do
      grid = make_grid(6, 20)
      write_line(grid, 4, " Status text  ", bg: "blue")
      write_line(grid, 5, " ") # empty last row
      selector = described_class.new(make_state(grid: grid, rows: 6))
      bars = selector.statusbars
      expect(bars.size).to eq(1)
      expect(bars.first.row).to eq(4)
      expect(bars.first.text).to include("Status text")
    end

    it "detects statusbar without bg info via fallback (≥30 chars)" do
      grid = make_grid(5, 60)
      write_line(grid, 4, "? for shortcuts | mock ctx ░░░░░░░░░░ 0%     ")
      selector = described_class.new(make_state(grid: grid, rows: 5, cols: 60))
      bars = selector.statusbars
      expect(bars.size).to eq(1)
      expect(bars.first.text).to include("shortcuts")
      expect(bars.first.text).to include("0%")
    end

    it "does not detect short last row without bg as statusbar" do
      grid = make_grid(5, 20)
      write_line(grid, 4, "short text")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars).to be_empty
    end

    it "handles single-row grid without error" do
      grid = make_grid(1, 60)
      write_line(grid, 0, "short")
      selector = described_class.new(make_state(grid: grid, rows: 1, cols: 60))
      expect(selector.statusbars).to be_empty
      expect { selector.statusbars }.not_to raise_error
    end

    it "detects footer preceded by separator line (Karat-style)" do
      grid = make_grid(15, 60)
      write_line(grid, 11, "─" * 60)
      write_line(grid, 12, "  ? for shortcuts                          | mock  ctx ░░░░░░░░░░ 0%")
      selector = described_class.new(make_state(grid: grid, rows: 15, cols: 60))
      bars = selector.statusbars
      expect(bars.size).to eq(1)
      expect(bars.first.text).to include("shortcuts")
      expect(bars.first.text).to include("0%")
      expect(bars.first.row).to eq(12)
    end

    it "skips separator line followed by empty row" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "──────")
      write_line(grid, 3, "      ") # empty
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars).to be_empty # falls through to fallback
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

  describe "#get_by_role with filters" do
    it "filters by text" do
      grid = make_grid(3, 30)
      write_line(grid, 1, "[ OK ]")
      write_line(grid, 2, "(Cancel)")
      selector = described_class.new(make_state(grid: grid))
      results = selector.get_by_role(:button, text: "OK")
      expect(results.size).to eq(1)
      expect(results.first.text).to eq("OK")
    end

    it "filters by checked state" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[x] Option A")
      write_line(grid, 2, "[ ] Option B")
      selector = described_class.new(make_state(grid: grid))
      checked = selector.get_by_role(:checkbox, checked: true)
      expect(checked.size).to eq(1)
      expect(checked.first.text).to eq("Option A")
    end

    it "filters by disabled state" do
      sel = described_class.allocate
      grid = make_grid(3, 20)
      sel.instance_variable_set(:@state, make_state(grid: grid))
      sel.instance_variable_set(:@elements, [
                                  TansParser::Element.new(role: :button, text: "A", row: 0, col: 0, width: 3,
                                                          height: 1, disabled: true,),
                                  TansParser::Element.new(role: :button, text: "B", row: 0, col: 5, width: 3,
                                                          height: 1,),
                                ],)
      expect(sel.get_by_role(:button, disabled: true).size).to eq(1)
      expect(sel.get_by_role(:button, disabled: true).first.text).to eq("A")
    end

    it "combines multiple filters" do
      sel = described_class.allocate
      grid = make_grid(3, 20)
      sel.instance_variable_set(:@state, make_state(grid: grid))
      sel.instance_variable_set(:@elements, [
                                  TansParser::Element.new(
                                    role: :checkbox, text: "Opt A", row: 0, col: 0,
                                    width: 5, height: 1, checked: true, disabled: false,
                                  ),
                                  TansParser::Element.new(
                                    role: :checkbox, text: "Opt B", row: 1, col: 0,
                                    width: 5, height: 1, checked: true, disabled: true,
                                  ),
                                ],)
      results = sel.get_by_role(:checkbox, checked: true, disabled: false)
      expect(results.size).to eq(1)
      expect(results.first.text).to eq("Opt A")
    end
  end

  describe "#get_by_role(:input)" do
    it "detects underscore-filled brackets as inputs" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[________]")
      selector = described_class.new(make_state(grid: grid))
      inputs = selector.inputs
      expect(inputs.size).to eq(1)
      expect(inputs.first.role).to eq(:input)
      expect(inputs.first.width).to eq(10)
    end

    it "detects multiple input fields" do
      grid = make_grid(5, 40)
      write_line(grid, 2, "Name: [______]  Email: [______]")
      selector = described_class.new(make_state(grid: grid))
      inputs = selector.inputs
      expect(inputs.size).to eq(2)
    end

    it "does not detect a button bracket as input" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.inputs).to be_empty
    end

    it "does not detect underscores as a button" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[____]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.buttons).to be_empty
      expect(selector.inputs.size).to eq(1)
    end
  end

  describe "#get_by_role(:label)" do
    it "detects name: pattern as a label" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "Username: ")
      selector = described_class.new(make_state(grid: grid))
      labels = selector.labels
      expect(labels.size).to eq(1)
      expect(labels.first.role).to eq(:label)
      expect(labels.first.text).to eq("Username")
    end

    it "detects multi-word labels with colon" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "First Name: ")
      selector = described_class.new(make_state(grid: grid))
      labels = selector.labels
      expect(labels.size).to eq(1)
      expect(labels.first.text).to eq("First Name")
    end

    it "detects colons in running text as labels" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "hello: world")
      selector = described_class.new(make_state(grid: grid))
      labels = selector.labels
      expect(labels.size).to eq(1)
      expect(labels.first.text).to eq("hello")
    end

    it "skips single-character labels" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "X: value")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.labels).to be_empty
    end
  end

  describe "#get_by_role(:menu)" do
    it "detects a menu bar on the first row" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "File    Edit    Help")
      selector = described_class.new(make_state(grid: grid))
      menus = selector.menus
      expect(menus.size).to eq(1)
      expect(menus.first.role).to eq(:menu)
      expect(menus.first.text).to include("File")
      expect(menus.first.text).to include("Edit")
    end

    it "detects dropdown items with > prefix" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "  > New File")
      write_line(grid, 2, "  > Open")
      selector = described_class.new(make_state(grid: grid))
      menus = selector.menus
      expect(menus.size).to eq(2)
      expect(menus.first.text).to eq("New File")
      expect(menus[1].text).to eq("Open")
    end

    it "returns empty when no menu patterns exist" do
      grid = make_grid(5, 30)
      write_line(grid, 0, "Welcome to the app")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.menus).to be_empty
    end
  end

  describe "#get_by_role(:tab)" do
    it "detects multiple closely-spaced brackets as tabs" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "[Tab1] [Tab2] [Tab3]")
      selector = described_class.new(make_state(grid: grid))
      tabs = selector.tabs
      expect(tabs.size).to eq(3)
      expect(tabs.map(&:role).uniq).to eq([:tab])
      expect(tabs.map(&:text)).to eq(%w[Tab1 Tab2 Tab3])
    end

    it "detects focused tab via underline" do
      grid = make_grid(5, 40)
      write_text(grid, 0, 0, "[Tab1]", underline: true)
      write_text(grid, 0, 7, "[Tab2]")
      selector = described_class.new(make_state(grid: grid))
      tabs = selector.tabs
      expect(tabs.size).to eq(2)
      expect(tabs.first.focused).to be true
      expect(tabs[1].focused).to be false
    end

    it "does not detect scattered buttons as tabs" do
      grid = make_grid(3, 40)
      write_line(grid, 1, "[ OK ]         (Cancel)")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.tabs).to be_empty
    end

    it "skips underscore-only brackets in tabs" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "[____] [Tab2]")
      selector = described_class.new(make_state(grid: grid))
      tabs = selector.tabs
      expect(tabs.size).to eq(1)
      expect(tabs.first.text).to eq("Tab2")
    end

    it "returns empty when only one bracket exists" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[Tab1]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.tabs).to be_empty
    end
  end

  describe "#get_by_role(:input) via signals" do
    it "handles [____] with no other elements" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[____]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.inputs.size).to eq(1)
      expect(selector.inputs.first.text).to eq("")
    end
  end

  describe "singular convenience methods" do
    it "button returns first button or nil" do
      grid = make_grid(3, 30)
      write_line(grid, 1, "[ OK ]  (Cancel)")
      selector = described_class.new(make_state(grid: grid))
      btn = selector.button
      expect(btn).to be_a(TansParser::Element)
      expect(btn.text).to eq("OK")
    end

    it "button with text filter returns matching element" do
      grid = make_grid(3, 30)
      write_line(grid, 1, "[ OK ]  (Cancel)")
      selector = described_class.new(make_state(grid: grid))
      btn = selector.button(text: "Cancel")
      expect(btn).to be_a(TansParser::Element)
      expect(btn.text).to eq("Cancel")
    end

    it "button returns nil when no match" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "plain text")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.button).to be_nil
    end

    it "checkbox returns first checkbox or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[x] Option A")
      write_line(grid, 3, "[ ] Option B")
      selector = described_class.new(make_state(grid: grid))
      cb = selector.checkbox
      expect(cb).to be_a(TansParser::Element)
      expect(cb.text).to eq("Option A")
    end

    it "dialog returns first dialog or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│  Hello   │")
      write_line(grid, 3, "└──────────┘")
      selector = described_class.new(make_state(grid: grid))
      dlg = selector.dialog
      expect(dlg).to be_a(TansParser::Element)
      expect(dlg.text).to include("Hello")
    end

    it "input returns first input or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[________]")
      selector = described_class.new(make_state(grid: grid))
      inp = selector.input
      expect(inp).to be_a(TansParser::Element)
      expect(inp.role).to eq(:input)
    end

    it "tab returns first tab or nil" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "[Tab1] [Tab2]")
      selector = described_class.new(make_state(grid: grid))
      t = selector.tab
      expect(t).to be_a(TansParser::Element)
      expect(t.text).to eq("Tab1")
    end

    it "menu returns first menu or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "  > Open")
      selector = described_class.new(make_state(grid: grid))
      m = selector.menu
      expect(m).to be_a(TansParser::Element)
      expect(m.text).to eq("Open")
    end

    it "label returns first label or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "Name: [______]")
      selector = described_class.new(make_state(grid: grid))
      l = selector.label
      expect(l).to be_a(TansParser::Element)
      expect(l.text).to eq("Name")
    end

    it "statusbar returns first statusbar or nil" do
      grid = make_grid(5, 20)
      write_line(grid, 4, " Ctrl+X Exit  ", bg: "blue")
      selector = described_class.new(make_state(grid: grid))
      sb = selector.statusbar
      expect(sb).to be_a(TansParser::Element)
      expect(sb.role).to eq(:statusbar)
    end

    it "progress_bar returns first progress bar or nil" do
      grid = make_grid(5, 30)
      write_line(grid, 2, "[#####     ]")
      selector = described_class.new(make_state(grid: grid))
      pb = selector.progress_bar
      expect(pb).to be_a(TansParser::Element)
      expect(pb.role).to eq(:progress)
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

  describe "negative / false-positive scenarios" do
    describe "buttons" do
      it "does not detect [*] checkbox marker as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[*]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end

      it "does not detect [x] checkbox marker as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[x]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end

      it "does not detect [X] checkbox marker as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[X]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end

      it "does not detect [ ] checkbox marker as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[ ]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end

      it "does not detect [12] numeric-only brackets as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[12]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end

      it "does not detect underscore-filled brackets as button" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "[______]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.buttons).to be_empty
      end
    end

    describe "labels" do
      it "does not detect URL scheme as label" do
        grid = make_grid(3, 40)
        write_line(grid, 1, "Visit https://example.com for more info")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.labels).to be_empty
      end

      it "does not detect time patterns as labels" do
        grid = make_grid(3, 40)
        write_line(grid, 1, "Meeting at 3:00 PM tomorrow")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.labels).to be_empty
      end
    end

    describe "progress bars" do
      it "does not detect [##] short bracket as progress bar" do
        grid = make_grid(3, 10)
        write_line(grid, 1, "[##]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.progress_bars).to be_empty
      end
    end

    describe "tabs" do
      it "does not detect brackets on different rows as tabs" do
        grid = make_grid(3, 20)
        write_line(grid, 0, "[Tab1]")
        write_line(grid, 1, "[Tab2]")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.tabs).to be_empty
      end
    end

    describe "menus" do
      it "does not detect prompt-like angle bracket without text as menu" do
        grid = make_grid(3, 20)
        write_line(grid, 1, "> ")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.menus).to be_empty
      end

      it "does not detect empty menu bar row" do
        grid = make_grid(3, 40)
        write_line(grid, 0, "                    ")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.menus).to be_empty
      end
    end

    describe "statusbar" do
      it "does not detect white text on default background as statusbar" do
        grid = make_grid(5, 20)
        write_line(grid, 4, "Status: idle")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.statusbars).to be_empty
      end
    end

    describe "dialogs" do
      it "does not detect incomplete box with only left border" do
        grid = make_grid(5, 20)
        write_line(grid, 1, "┌── text here")
        write_line(grid, 2, "│  more text ")
        selector = described_class.new(make_state(grid: grid))
        expect(selector.dialogs).to be_empty
      end

      it "does not detect box where bottom border is at wrong column" do
        grid = make_grid(5, 30)
        write_line(grid, 1, " ┌──────────┐")
        write_line(grid, 2, " │  Hello   │")
        write_line(grid, 3, "  └──────────┘") # offset by one column
        selector = described_class.new(make_state(grid: grid))
        expect(selector.dialogs).to be_empty
      end
    end
  end

  describe "confidence scoring" do
    it "assigns higher confidence to square-bracket buttons" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ OK ]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.buttons.first.confidence).to eq(0.9)
    end

    it "assigns medium confidence to round-bracket buttons" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "(Cancel)")
      selector = described_class.new(make_state(grid: grid))
      btn = selector.buttons.find { |b| b.text == "Cancel" }
      expect(btn.confidence).to eq(0.85)
    end

    it "assigns lower confidence to angle-bracket buttons" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "<Submit>")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.buttons.first.confidence).to eq(0.75)
    end

    it "penalizes single-character button text" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[A]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.buttons.first.confidence).to eq(0.7) # 0.9 - 0.2
    end

    it "assigns high confidence to checked checkboxes" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[x] Option")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.checkboxes.first.confidence).to eq(0.9)
    end

    it "assigns slightly lower confidence to unchecked checkboxes" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[ ] Option")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.checkboxes.first.confidence).to eq(0.85)
    end

    it "assigns high confidence to dialogs" do
      grid = make_grid(5, 20)
      write_line(grid, 1, "┌──────────┐")
      write_line(grid, 2, "│  Hello   │")
      write_line(grid, 3, "└──────────┘")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.dialogs.first.confidence).to eq(0.9)
    end

    it "gives confidence bonus for titled dialogs" do
      grid = make_grid(5, 40)
      write_line(grid, 1, "╭─ Commands ────────────────────╮")
      write_line(grid, 2, "│  Hello                       │")
      write_line(grid, 3, "╰───────────────────────────────╯")
      selector = described_class.new(make_state(grid: grid, rows: 5, cols: 40))
      expect(selector.dialogs.first.confidence).to eq(0.95)
    end

    it "assigns high confidence to statusbar with inverse colors" do
      grid = make_grid(5, 20)
      write_line(grid, 4, " Ctrl+X Exit  ", bg: "blue")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars.first.confidence).to eq(0.9)
    end

    it "assigns low confidence to statusbar fallback (no bg)" do
      grid = make_grid(5, 60)
      write_line(grid, 4, "? for shortcuts | mock ctx ░░░░░░░░░░ 0%     ")
      selector = described_class.new(make_state(grid: grid, rows: 5, cols: 60))
      expect(selector.statusbars.first.confidence).to eq(0.5)
    end

    it "assigns medium-high confidence to separator-preceded footer" do
      grid = make_grid(5, 40)
      write_line(grid, 2, "─" * 40)
      write_line(grid, 3, "  Status: idle                            ")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.statusbars.first.confidence).to eq(0.85)
    end

    it "assigns high confidence to inputs" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[________]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.inputs.first.confidence).to eq(0.9)
    end

    it "assigns full confidence to annotations" do
      grid = make_grid(3, 20)
      state = make_state(grid: grid)
      state.annotate_role(:button, row: 0, col: 0, width: 4, height: 1, text: "Manual")
      selector = described_class.new(state)
      ann = selector.buttons.find { |b| b.text == "Manual" }
      expect(ann.confidence).to eq(1.0)
    end

    it "annotations can override confidence" do
      grid = make_grid(3, 20)
      state = make_state(grid: grid)
      state.annotate_role(:button, row: 0, col: 0, width: 4, height: 1, text: "Maybe", confidence: 0.6)
      selector = described_class.new(state)
      ann = selector.buttons.find { |b| b.text == "Maybe" }
      expect(ann.confidence).to eq(0.6)
    end

    it "assigns confidence to labels" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "Username: ")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.labels.first.confidence).to eq(0.8)
    end

    it "assigns higher confidence to multi-word labels" do
      grid = make_grid(3, 30)
      write_line(grid, 1, "First Name: ")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.labels.first.confidence).to eq(0.85)
    end

    it "assigns confidence to menu bars" do
      grid = make_grid(3, 40)
      write_line(grid, 0, "File    Edit    Help")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.menus.first.confidence).to eq(0.9)
    end

    it "assigns lower confidence to 2-item menu bars" do
      grid = make_grid(3, 30)
      write_line(grid, 0, "File    Edit")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.menus.first.confidence).to eq(0.85)
    end

    it "assigns confidence to dropdown items" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "  > Open")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.menus.first.confidence).to eq(0.8)
    end

    it "assigns confidence to tabs" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "[Tab1] [Tab2]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.tabs.first.confidence).to eq(0.7)
    end

    it "assigns higher confidence to many tabs" do
      grid = make_grid(5, 40)
      write_line(grid, 0, "[Tab1] [Tab2] [Tab3]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.tabs.first.confidence).to eq(0.85)
    end

    it "gives confidence bonus for focused tab" do
      grid = make_grid(5, 40)
      write_text(grid, 0, 0, "[Tab1]", underline: true)
      write_text(grid, 0, 7, "[Tab2]")
      selector = described_class.new(make_state(grid: grid))
      focused = selector.tabs.find { |t| t.focused }
      expect(focused.confidence).to eq(0.75) # 0.7 + 0.05
    end

    it "assigns confidence to progress bars" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[#####     ]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.progress_bars.first.confidence).to eq(0.9)
    end

    it "assigns higher confidence to complete progress bars" do
      grid = make_grid(3, 20)
      write_line(grid, 1, "[##########]")
      selector = described_class.new(make_state(grid: grid))
      expect(selector.progress_bars.first.confidence).to eq(0.95)
    end
  end

  describe "annotations from State" do
    it "picks up manually annotated roles" do
      grid = make_grid(5, 30)
      state = make_state(grid: grid)
      state.annotate_role(:dialog, row: 1, col: 2, width: 20, height: 5, text: "HelpBox")
      selector = described_class.new(state)
      dialogs = selector.dialogs
      expect(dialogs.size).to eq(1)
      expect(dialogs.first.role).to eq(:dialog)
      expect(dialogs.first.text).to eq("HelpBox")
    end

    it "annotations coexist with auto-detected elements" do
      grid = make_grid(5, 30)
      write_line(grid, 1, "[ OK ]")
      state = make_state(grid: grid)
      state.annotate_role(:button, row: 0, col: 0, width: 4, height: 1, text: "Extra")
      selector = described_class.new(state)
      expect(selector.buttons.size).to eq(2) # one auto, one manual
    end

    it "annotations accept checked and disabled states" do
      grid = make_grid(3, 20)
      state = make_state(grid: grid)
      state.annotate_role(:checkbox, row: 0, col: 0, width: 5, height: 1,
                                     text: "Option", checked: true, disabled: false,)
      selector = described_class.new(state)
      cb = selector.checkbox
      expect(cb.checked?).to be true
      expect(cb.disabled?).to be false
    end

    it "annotation filters work with get_by_role" do
      grid = make_grid(3, 30)
      state = make_state(grid: grid)
      state.annotate_role(:button, row: 0, col: 0, width: 4, height: 1, text: "Save")
      state.annotate_role(:button, row: 0, col: 10, width: 4, height: 1, text: "Cancel")
      selector = described_class.new(state)
      expect(selector.get_by_role(:button, text: "Save").size).to eq(1)
    end
  end
end
# rubocop:enable Metrics/ParameterLists

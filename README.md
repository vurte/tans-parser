# tans-parser

Parse raw terminal output with ANSI escape sequences into structured, queryable data.
Recognizes UI elements heuristically for AI-driven terminal interaction.

## Installation

Ruby 3.0+ required.

```bash
gem install tans-parser
```

## Usage

### Parse ANSI output

```ruby
require "tans-parser"

# Parse a raw ANSI string into a structured grid
raw = "\e[31mERROR:\e[0m Something went wrong\n\e[32mOK:\e[0m All good"
state_data = TansParser::ANSIParser.parse(raw, rows: 40, cols: 120)

# state_data is a Hash with:
#   :size   → {rows:, cols:}
#   :cursor → {row:, col:, visible:, style:}
#   :rows   → [[{char:, fg:, bg:, bold:, italic:, underline:, blink:}, ...], ...]
```

### Query the state

```ruby
state = TansParser::State.new(state_data)

# Plain text of the entire screen
state.plain_text
# => "ERROR: Something went wrong\nOK: All good"

# Text search — three match modes
state.find_text("ERROR")                        # :partial (default) — substring
state.find_text("ERROR", match: :exact)         # :exact — row text must equal
state.find_text("\\d+", match: :regex)          # :regex — compile string to Regexp
state.find_text(/\d{3}/)                        # Regexp object also supported
# => [{row:, col:, text:, full_line:}, ...]

# Cell-level queries
state.foreground_at(0, 0)  # => "red"
state.background_at(0, 0)  # => "default"
state.style_at(0, 0)       # => {bold: false, italic: false, underline: false}

# JSON with highlights
state.to_ai_json
# => {size:, cursor:, text:, highlights:, summary:}
```

### Rebuild ANSI from state

```ruby
ansi = TansParser::ANSIParser.build_frame(state_data)
# => "\e[0m\e[2J\e[H\e[31mE\e[31mR\e[31mR..."
```

### Color utilities

```ruby
include TansParser::ANSIUtils

resolve_color("red", nil)       # => [0xAA, 0x00, 0x00]
resolve_color("#ff8800", nil)   # => [255, 136, 0]
resolve_color("color82", nil)   # => [95, 255, 0]
xterm_256(16)                   # => [0x00, 0x00, 0x00]
```

### Element recognition

```ruby
state = TansParser::State.new(state_data)
selector = TansParser::Selector.new(state)

# Find UI elements by role (plural — returns Array)
selector.buttons       # [ OK ], (Cancel), <Submit>
selector.checkboxes    # [x], [*], [ ] at line starts
selector.inputs        # [________] underscore-filled brackets
selector.labels        # Name: patterns (text followed by colon)
selector.menus         # Menu bars (row 0–1) and > dropdown items
selector.tabs          # Closely-spaced [Tab1] [Tab2] brackets
selector.dialogs       # Box-drawing character regions (┌─┐│└┘)
selector.statusbars    # Bottom row with non-default background
selector.progress_bars # [####   ], [====>  ] patterns

# Singular convenience methods — return Element or nil
selector.button                   # first button
selector.checkbox(text: "Save")   # first matching checkbox
selector.input                    # first input
selector.dialog                   # first dialog
selector.tab                      # first tab
# ... label, menu, statusbar, progress_bar
```

### Element filtering

```ruby
# get_by_role with optional filters
selector.get_by_role(:button, text: "OK")          # text filter (partial match)
selector.get_by_role(:checkbox, checked: true)     # checked state filter
selector.get_by_role(:button, disabled: false)     # disabled state filter

# Combined filters
selector.get_by_role(:checkbox, checked: true, text: "auto-save")

# Plural methods also accept filters
selector.checkboxes(checked: false)   # unchecked only
selector.buttons(text: "Save")        # buttons with matching text
```

### Scoping (within)

Restrict searches to an element's bounding box:

```ruby
dialog = selector.dialog

# With block
selector.within(dialog) do |scope|
  scope.buttons       # only buttons inside the dialog
  scope.find_text("OK")
  scope.button        # singular — first button inside dialog
end

# Without block — returns ScopedSelector
scoped = selector.within(dialog)
scoped.get_by_role(:button)
scoped.find_text("Retry", match: :exact)
```

### Custom role registration

When heuristic detection fails, annotate grid regions manually:

```ruby
state = TansParser::State.new(state_data)

# Annotate a dialog that heuristics didn't recognize
state.annotate_role(:dialog, row: 5, col: 20, width: 28, height: 5, text: "Help")
state.annotate_role(:statusbar, row: 24, col: 0, width: 80, height: 1)

# Selector picks up annotations alongside auto-detected elements
selector = TansParser::Selector.new(state)
selector.dialogs     # => includes annotated dialog
selector.statusbars  # => includes annotated statusbar

# Annotations accept extra attributes
state.annotate_role(:button, row: 0, col: 0, width: 6, height: 1,
                    text: "Submit", fg: "green", disabled: false)
```

### State comparison (diff)

Compare two terminal states cell-by-cell:

```ruby
before = TansParser::State.new(state_data)
# ... some action changes the screen ...
after = TansParser::State.new(new_state_data)

# Full diff — compares all cell keys
diff = before.diff(after)
# => [{row: 3, col: 2, before: {char: "T", fg: "default", ...},
#                        after:  {char: "X", fg: "default", ...}}]

# Chars-only diff — ignores color/style changes
diff = before.diff(after, chars_only: true)
# Only reports actual character differences

# Ignore specific rows — useful for cursor/prompt lines
diff = before.diff(after, chars_only: true, ignore_rows: [prompt_row])

# Accepts raw hash as argument
diff = before.diff({size: {rows: 5, cols: 10}, cursor: {...}, rows: [...]})
```

### Element actions & attributes

Each `TansParser::Element` is a Struct with data and action methods:

```ruby
el = selector.buttons.first

# Data attributes
el.role      # => :button
el.text      # => "OK"
el.row       # => 1
el.col       # => 2
el.width     # => 4
el.height    # => 1
el.checked   # => true/false/nil
el.focused   # => true/false/nil
el.disabled  # => true/false/nil
el.fg        # => "default"
el.bg        # => "default"
el.to_h      # => {role: :button, text: "OK", row: 1, col: 2, ...}

# Predicates
el.checked?   # => false (always boolean)
el.disabled?  # => false (always boolean)

# Geometry
el.bounds     # => {row: 1, col: 2, width: 4, height: 1}

# Actions — return descriptive hashes for AI consumption
el.click            # => {action: :click, target: el, row: 1, col: 4}
el.type("hello")    # => {action: :type, target: el, row: 1, col: 4, text: "hello"}
el.press_key(:tab)  # => {action: :press_key, target: el, key: :tab}
```

### Recognized element patterns

| Role | Pattern | Example |
|------|---------|---------|
| `:button` | `[...]`, `(...)`, `<...>` | `[ OK ]`, `(Cancel)`, `<Submit>` |
| `:checkbox` | `[x]`, `[*]`, `[X]`, `[ ]` + label | `[x] Enable logging` |
| `:input` | `[_+]` inside brackets | `[________]` |
| `:label` | `Word:` or `Multiple Words:` | `Project Name:` |
| `:menu` | Menu bar (row 0–1, spaced words) or `> Item` | `File  Edit  Help`, `> New File` |
| `:tab` | ≥2 closely-spaced `[...]` on one row | `[Tab1] [Tab2] [Tab3]` |
| `:dialog` | Unicode box-drawing borders | `┌──┐` `│  │` `└──┘` |
| `:statusbar` | Last row with ≥3 non-default-bg cells | Inverse status line |
| `:progress` | `[###...]` with `#`, `>`, `=`, `-` fill | `[#####     ]  50%` |

## Cell format

Each cell is a Hash with these keys:

| Key | Type | Description |
|-----|------|-------------|
| `char` | String | Single character (UTF-8) |
| `fg` | String | Foreground color name, hex, or "colorN" |
| `bg` | String | Background color name, hex, or "colorN" |
| `bold` | Boolean | Bold style |
| `italic` | Boolean | Italic style |
| `underline` | Boolean | Underline style |
| `blink` | Boolean | Blink style |
| `width` | Integer | Display width (1 for normal, 2 for CJK/emoji, 0 for continuation) |

Default cell: `{char: " ", fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: false, width: 1}`

## Supported ANSI sequences

- **SGR** — colors (16, 256, TrueColor), bold, italic, underline, blink, reverse
- **Cursor** — CUU, CUD, CUF, CUB, CUP, CHA
- **Erase** — ED (erase display), EL (erase line), ECH (erase characters)
- **Scroll** — scroll regions (DECSTBM), overflow scrolling
- **Alt screen** — DEC private modes 47, 1047, 1049
- **Cursor save/restore** — DECSC, DECRC, CSI s, CSI u
- **Cursor style** — DECSCUSR
- **Mouse tracking** — DEC private modes 1000, 1002, 1003, 1006
- **ISO 2022** — G0/G1 charset switching, DEC Special Graphics
- **UTF-8** — Multi-byte characters including CJK, emoji (correct display width via `unicode-display_width`)
- **Combining characters** — Zero-width combining marks appended to previous cell

## License

MIT

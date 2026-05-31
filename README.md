# tans-parser

Parse raw terminal output with ANSI escape sequences into structured, queryable data.

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

# Search for text
state.find_text("ERROR")
# => [{row: 0, col: 0, text: "ERROR", full_line: "ERROR: Something went wrong"}]

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

Default cell: `{char: " ", fg: "default", bg: "default", bold: false, italic: false, underline: false, blink: false}`

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
- **UTF-8** — Multi-byte characters including emoji

## License

MIT

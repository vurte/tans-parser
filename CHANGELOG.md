# CHANGELOG

## 0.1.4

- **Unicode width support** — correct display width for CJK, emoji, and combining characters:
  - `unicode-display_width` gem as runtime dependency (~> 2.5)
  - `:width` key in cell hash (1 or 2) and `default_cell`
  - Cursor advances by display width instead of always +1
  - Wide chars (CJK/emoji) clear continuation cells
  - Combining characters (zero-width) appended to previous cell
  - Bugfix: parse loop uses `bytesize` to handle multi-byte chars at start of string
- 4 new tests, 329 total, 100% line and branch coverage maintained

## 0.1.3

- **Dialog recognition** — extended box-drawing character support and titled borders:
  - Added rounded corners (`╭╮╰╯`) and double-line (`╔╗╚╝`)
  - `TOP_LEFT_CORNERS` extended with `╭╔╓╒`
  - `dialog_top_width` extended with `╮╗╖╕` (top-right) and `═` (double horizontal)
  - Supports titled borders: finds first top-right corner anywhere on line (e.g. `╭─ Commands ─╮`)
- **Statusbar recognition** — more flexible detection:
  - Checks last 2 rows instead of only the last row
  - Fallback: detects last row as statusbar if it has ≥30 characters of content, even without background color info
  - Separator-preceded footers: scans all rows for footer after `───` separator line (Karat-style)
- **Custom role registration** — `State#annotate_role(role, row:, col:, width:, height:, text:, **extra)`:
  - Manually annotate grid regions with semantic roles
  - `Selector#detect_annotations` picks them up during `scan` alongside auto-detected elements
  - Annotations support filters (text, checked, disabled) and all convenience methods
- **State#diff** — cell-level comparison between two State instances:
  - `diff(other_state)` — compares all 7 cell keys (`char`, `fg`, `bg`, `bold`, `italic`, `underline`, `blink`)
  - `diff(other_state, chars_only: true)` — compares only `:char`, ignores style/color changes
  - `diff(other_state, ignore_rows: [2, 5])` — skips specified rows (e.g. cursor/prompt lines)
  - Handles different grid sizes (fills missing cells with `DEFAULT_CELL`)
  - Accepts raw hash or State object
- 25 new tests, 325 total, 100% line and branch coverage maintained

## 0.1.2

- **Flexible text search** — `State#find_text(pattern, match: :partial)` with three modes:
  - `:partial` (default) — substring match (unchanged)
  - `:exact` — row text must equal pattern (ignoring trailing whitespace)
  - `:regex` — compile String to Regexp for matching
  - Regexp objects now return the actual matched substring in `result[:text]`
- **Enhanced `get_by_role`** — filter keyword arguments:
  - `text:` — partial match on element text
  - `checked:` — filter by checked state (`true`/`false`)
  - `disabled:` — filter by disabled state (`true`/`false`)
  - All plural convenience methods (`buttons`, `checkboxes`, etc.) accept the same filters
- **New UI element roles**:
  - `:input` — `[________]` underscore-filled brackets (text input fields)
  - `:label` — `Word:` or `Multiple Words:` patterns
  - `:menu` — menu bars (row 0–1, spaced words) and `> Item` dropdown items
  - `:tab` — closely-spaced `[Tab1] [Tab2]` brackets, with `focused` detection via underline/background
- **Singular convenience methods** — return first matching Element or `nil`:
  - `button`, `checkbox`, `input`, `dialog`, `label`, `menu`, `tab`, `statusbar`, `progress_bar`
  - All accept the same filter kwargs (`text:`, `checked:`, `disabled:`)
  - Existing plural methods (`buttons`, `checkboxes`, etc.) unchanged
- **Element actions** — `Element` now has action methods returning descriptive hashes:
  - `click` → `{action: :click, target:, row:, col:}`
  - `type(text)` → `{action: :type, target:, row:, col:, text:}`
  - `press_key(key)` → `{action: :press_key, target:, key:}`
- **Element predicates** — `checked?` and `disabled?` (always return boolean)
- **Element `bounds`** — returns `{row:, col:, width:, height:}`
- **`disabled` field** — added to Element struct
- **Scoping (`within`)** — `Selector#within(element, &block)` with `TansParser::ScopedSelector`:
  - `get_by_role`, `get_by_text`, `find_text` restricted to element's bounding box
  - All convenience methods (singular + plural) available inside scope
  - Works with or without block
- **Button detection** — now skips checkbox markers (`[x]`, `[X]`, `[*]`, `[ ]`) and underscore-only brackets
- 105 new tests, 100% line and branch coverage maintained (300 total)

## 0.1.1

- `TansParser::Element` — value object for recognized UI elements (role, text, position, size, colors)
- `TansParser::Selector` — scans terminal state for recognized UI elements:
  - Buttons (`[ OK ]`, `(Cancel)`, `<Submit>`)
  - Checkboxes (`[x]`, `[*]`, `[ ]` at line starts)
  - Dialogs (box-drawing character regions)
  - Statusbars (bottom row with non-default background)
  - Progress bars (`[####   ]`, `[====>  ]` patterns)
- Query API: `get_by_text`, `get_by_role`, convenience accessors (`buttons`, `checkboxes`, `dialogs`, `statusbars`, `progress_bars`)
- `Element#to_h` with nil-value exclusion via `.compact`
- 36 new tests for selector and element, 100% line and branch coverage maintained

## 0.1.0

- Initial release: ANSI escape sequence parser extracted from tui-td
- `TansParser::ANSIParser` — parses raw terminal output into structured state (735 lines)
- `TansParser::ANSIUtils` — shared ANSI color and style helpers (77 lines)
- `TansParser::State` — high-level query API for terminal state (148 lines)
- Zero runtime dependencies (pure Ruby stdlib)
- 188 tests with 100% line and branch coverage
- SGR colors (16, 256, TrueColor), cursor movement, erase, scroll
- Alternate screen buffer support (DEC private modes 47, 1047, 1049)
- ISO-2022 charset switching (G0/G1, DEC Special Character & Line Drawing)
- Mouse tracking mode/format parsing (1000, 1002, 1003, 1006)
- DECSC/DECRC cursor save/restore (ESC 7/8 and CSI s/u variants)
- DECSTBM scroll region support
- DSR (Device Status Report) detection
- `build_frame` — reconstruct ANSI output from state hash
- `_color_code` — convert named/hex colors to ANSI color sequences
- UTF-8 multi-byte character support
- RuboCop, Reek, Bundler-Audit configured

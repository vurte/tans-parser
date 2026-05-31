# CHANGELOG

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

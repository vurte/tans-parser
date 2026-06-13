#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require_relative "../lib/tans-parser"

def grid(rows, cols)
  Array.new(rows) { Array.new(cols) { { char: " ", fg: "default", bg: "default", bold: false, italic: false, underline: false } } }
end

def write(g, r, c, s, **opts)
  s.chars.each_with_index { |ch, i| g[r][c + i] = { char: ch, fg: "default", bg: "default", bold: false, italic: false, underline: false }.merge(opts) }
end

g = grid(24, 80)
write(g, 0, 0, "[Tab1] [Tab2] [Tab3]")
write(g, 3, 2, "╭─ Dialog Title ───────────────────────────╮")
write(g, 4, 2, "│  [x] Enable auto-save                   │")
write(g, 5, 2, "│  [ ] Show hidden files                  │")
write(g, 6, 2, "│  [x] Dark mode                          │")
write(g, 7, 2, "│                                          │")
write(g, 8, 2, "│  [ OK ]  (Cancel)  <Help>               │")
write(g, 9, 2, "╰──────────────────────────────────────────╯")
write(g, 12, 0, "Username: [________]  Password: [________]")
write(g, 14, 5, "[#####     ] 50%")
write(g, 23, 0, " Ctrl+X Exit | ? for help  ", bg: "blue")

s = TansParser::State.new(size: { rows: 24, cols: 80 }, cursor: { row: 0, col: 0 }, rows: g)

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)
  x.report("selector scan 80x24") { TansParser::Selector.new(s) }
  x.compare!
end

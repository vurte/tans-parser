#!/usr/bin/env ruby
# frozen_string_literal: true

require "benchmark/ips"
require_relative "../lib/tans-parser"

def build_state(fill, rows, cols)
  grid = Array.new(rows) do |r|
    Array.new(cols) do |c|
      { char: (c < 30 ? fill : " "), fg: r < 3 ? "default" : "white",
        bg: "default", bold: r.zero?, italic: false, underline: false, blink: false }
    end
  end
  TansParser::State.new(size: { rows: rows, cols: cols }, cursor: { row: 0, col: 0 }, rows: grid)
end

A = build_state("x", 24, 80)
B = build_state("y", 24, 80)

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)
  x.report("diff 80x24 (full)") { A.diff(B) }
  x.report("diff 80x24 (chars_only)") { A.diff(B, chars_only: true) }
  x.report("diff 80x24 (ignore 2 rows)") { A.diff(B, ignore_rows: [0, 1]) }
  x.compare!
end

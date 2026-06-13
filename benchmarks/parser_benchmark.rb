#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: ANSI parser throughput for typical terminal workloads.
#
# Run: bundle exec ruby benchmarks/parser_benchmark.rb

require "benchmark/ips"
require_relative "../lib/tans-parser"

# --- Test data --------------------------------------------------------------

PLAIN_TEXT = "hello world\n" * 24
PLAIN_TEXT.freeze

ANSI_COLORS = Array.new(24) { |i|
  "\e[#{31 + (i % 6)}mLine #{i + 1}: some colored output here\e[0m\n"
}.join.freeze

ANSI_CURSOR = "First line\n" \
              "\e[2;5HSecond line at (2,5)\n" \
              "\e[3;10HThird line at (3,10)\n" \
              "\e[2ACursor up two\n" \
              "\e[BDown one\n" \
              "\e[4CFour to the right\n" * 5
ANSI_CURSOR.freeze

COMPLEX_ANSI = Array.new(24) { |i|
  "\e[1;#{31 + (i % 6)}mBold #{i + 1}: \e[4munderlined\e[24m text " \
  "\e[48;5;#{ (i * 10) % 256 }m  BG color  \e[0m\n"
}.join.freeze

DIALOG_OUTPUT = <<~ANSI.freeze
  \e[2J\e[H
  ╭─ Commands ─────────────────────────────╮
  │                                        │
  │  [x] Enable auto-save on exit          │
  │  [ ] Show hidden files                 │
  │                                        │
  │  [ OK ]  (Cancel)  <Help>              │
  │                                        │
  ╰────────────────────────────────────────╯
  \e[25;1H Ctrl+X Exit | ? for help  \e[7m░░░░░\e[27m 0%
ANSI

# --- Benchmarks -------------------------------------------------------------

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)

  x.report("plain 80x24") do
    TansParser::ANSIParser.parse(PLAIN_TEXT, 24, 80)
  end

  x.report("ANSI colors 80x24") do
    TansParser::ANSIParser.parse(ANSI_COLORS, 24, 80)
  end

  x.report("cursor heavy 80x24") do
    TansParser::ANSIParser.parse(ANSI_CURSOR, 24, 80)
  end

  x.report("complex ANSI 80x24") do
    TansParser::ANSIParser.parse(COMPLEX_ANSI, 24, 80)
  end

  x.report("dialog-like 80x30") do
    TansParser::ANSIParser.parse(DIALOG_OUTPUT, 30, 80)
  end

  x.compare!
end

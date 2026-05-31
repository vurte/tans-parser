# frozen_string_literal: true

require "spec_helper"
require "tans_parser/ansi_utils"

RSpec.describe TansParser::ANSIUtils do
  let(:dummy) { Class.new { include TansParser::ANSIUtils }.new }

  describe "#resolve_color" do
    it "returns fallback for 'default'" do
      fallback = [1, 2, 3]
      expect(dummy.resolve_color("default", fallback)).to eq(fallback)
    end

    it "resolves standard ANSI names" do
      expect(dummy.resolve_color("red", nil)).to eq([0xAA, 0x00, 0x00])
      expect(dummy.resolve_color("green", nil)).to eq([0x00, 0xAA, 0x00])
      expect(dummy.resolve_color("blue", nil)).to eq([0x00, 0x00, 0xAA])
    end

    it "resolves bright ANSI names" do
      expect(dummy.resolve_color("bright_white", nil)).to eq([0xFF, 0xFF, 0xFF])
      expect(dummy.resolve_color("bright_red", nil)).to eq([0xFF, 0x55, 0x55])
    end

    it "resolves TrueColor hex format" do
      expect(dummy.resolve_color("#ff8800", nil)).to eq([255, 136, 0])
      expect(dummy.resolve_color("#ABCDEF", nil)).to eq([0xAB, 0xCD, 0xEF])
    end

    it "resolves 256-color format (colorN)" do
      expect(dummy.resolve_color("color1", nil)).to eq([0xAA, 0x00, 0x00])
    end

    it "resolves 256-color cube index" do
      expect(dummy.resolve_color("color16", nil)).to eq([0x00, 0x00, 0x00])
    end

    it "resolves unknown names to fallback" do
      fallback = [0xCC, 0xCC, 0xCC]
      expect(dummy.resolve_color("nonexistent", fallback)).to eq(fallback)
    end
  end

  describe "#xterm_256" do
    it "maps 0-15 to standard ANSI colors" do
      expect(dummy.xterm_256(0)).to eq([0x00, 0x00, 0x00])
      expect(dummy.xterm_256(1)).to eq([0xAA, 0x00, 0x00])
      expect(dummy.xterm_256(7)).to eq([0xAA, 0xAA, 0xAA])
      expect(dummy.xterm_256(8)).to eq([0x55, 0x55, 0x55])
      expect(dummy.xterm_256(15)).to eq([0xFF, 0xFF, 0xFF])
    end

    it "computes cube colors for 16-231" do
      expect(dummy.xterm_256(16)).to eq([0x00, 0x00, 0x00])
      expect(dummy.xterm_256(51)).to eq([0x00, 0xFF, 0xFF])
    end

    it "computes grayscale for 232-255" do
      expect(dummy.xterm_256(232)).to eq([8, 8, 8])
      expect(dummy.xterm_256(255)).to eq([238, 238, 238])
    end
  end

  describe "#_dig" do
    it "traverses symbol keys" do
      hash = { a: { b: { c: 42 } } }
      expect(dummy._dig(hash, :a, :b, :c)).to eq(42)
    end

    it "traverses string keys" do
      hash = { "a" => { "b" => "value" } }
      expect(dummy._dig(hash, "a", "b")).to eq("value")
    end

    it "falls back to string key if symbol key missing" do
      hash = { "name" => "fallback value" }
      expect(dummy._dig(hash, :name)).to eq("fallback value")
    end

    it "returns nil for missing keys" do
      hash = { a: 1 }
      expect(dummy._dig(hash, :b)).to be_nil
    end

    it "returns nil when hash is nil" do
      expect(dummy._dig(nil, :any)).to be_nil
    end
  end

  describe "constants" do
    it "ANSI_RGB has all 16 entries" do
      expect(TansParser::ANSIUtils::ANSI_RGB.size).to eq(16)
    end

    it "CUBE has correct values" do
      expect(TansParser::ANSIUtils::CUBE).to eq([0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF])
    end

    it "ANSI_INDEX maps indices correctly" do
      expect(TansParser::ANSIUtils::ANSI_INDEX[0]).to eq("black")
      expect(TansParser::ANSIUtils::ANSI_INDEX[7]).to eq("white")
      expect(TansParser::ANSIUtils::ANSI_INDEX[8]).to eq("bright_black")
      expect(TansParser::ANSIUtils::ANSI_INDEX[15]).to eq("bright_white")
    end

    it "DEFAULT_FG and DEFAULT_BG are defined" do
      expect(TansParser::ANSIUtils::DEFAULT_FG).to eq([0xC0, 0xC0, 0xC0])
      expect(TansParser::ANSIUtils::DEFAULT_BG).to eq([0x00, 0x00, 0x00])
    end
  end
end

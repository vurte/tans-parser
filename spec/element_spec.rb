# frozen_string_literal: true

require "spec_helper"

RSpec.describe TansParser::Element do
  describe "fields" do
    it "has role, text, position, size, and state fields" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      expect(el.role).to eq(:button)
      expect(el.text).to eq("OK")
      expect(el.row).to eq(0)
      expect(el.col).to eq(0)
      expect(el.width).to eq(4)
      expect(el.height).to eq(1)
    end

    it "defaults checked, focused, fg, bg, disabled to nil" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      expect(el.checked).to be_nil
      expect(el.focused).to be_nil
      expect(el.fg).to be_nil
      expect(el.bg).to be_nil
      expect(el.disabled).to be_nil
    end

    it "accepts disabled as true" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, disabled: true,
      )
      expect(el.disabled).to be true
    end

    it "accepts disabled as false" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, disabled: false,
      )
      expect(el.disabled).to be false
    end
  end

  describe "#checked?" do
    it "returns true when checked is true" do
      el = described_class.new(
        role: :checkbox, text: "Opt", row: 0, col: 0, width: 3, height: 1, checked: true,
      )
      expect(el.checked?).to be true
    end

    it "returns false when checked is false" do
      el = described_class.new(
        role: :checkbox, text: "Opt", row: 0, col: 0, width: 3, height: 1, checked: false,
      )
      expect(el.checked?).to be false
    end

    it "returns false when checked is nil" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      expect(el.checked?).to be false
    end
  end

  describe "#disabled?" do
    it "returns true when disabled is true" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, disabled: true,
      )
      expect(el.disabled?).to be true
    end

    it "returns false when disabled is false" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, disabled: false,
      )
      expect(el.disabled?).to be false
    end

    it "returns false when disabled is nil" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      expect(el.disabled?).to be false
    end
  end

  describe "#bounds" do
    it "returns a hash with row, col, width, height" do
      el = described_class.new(role: :dialog, text: "", row: 2, col: 5, width: 20, height: 5)
      expect(el.bounds).to eq({ row: 2, col: 5, width: 20, height: 5 })
    end
  end

  describe "#click" do
    it "returns an action hash with click and target" do
      el = described_class.new(role: :button, text: "OK", row: 3, col: 10, width: 6, height: 1)
      result = el.click
      expect(result[:action]).to eq(:click)
      expect(result[:target]).to eq(el)
      expect(result[:row]).to eq(3)
      expect(result[:col]).to eq(13) # col + width / 2 = 10 + 3
    end
  end

  describe "#type" do
    it "returns an action hash with type, target, and text" do
      el = described_class.new(role: :input, text: "", row: 2, col: 4, width: 20, height: 1)
      result = el.type("hello")
      expect(result[:action]).to eq(:type)
      expect(result[:target]).to eq(el)
      expect(result[:row]).to eq(2)
      expect(result[:col]).to eq(14) # col + width / 2 = 4 + 10
      expect(result[:text]).to eq("hello")
    end
  end

  describe "#press_key" do
    it "returns an action hash with press_key, target, and key" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      result = el.press_key(:enter)
      expect(result[:action]).to eq(:press_key)
      expect(result[:target]).to eq(el)
      expect(result[:key]).to eq(:enter)
    end
  end

  describe "#to_h" do
    it "excludes nil values" do
      el = described_class.new(role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1)
      hash = el.to_h
      expect(hash).to include(:role, :text, :row, :col, :width, :height)
      expect(hash).not_to have_key(:checked)
      expect(hash).not_to have_key(:disabled)
    end

    it "includes checked when true" do
      el = described_class.new(
        role: :checkbox, text: "Opt", row: 0, col: 0, width: 3, height: 1, checked: true,
      )
      expect(el.to_h).to have_key(:checked)
    end

    it "includes focused when true" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, focused: true,
      )
      expect(el.to_h).to have_key(:focused)
    end

    it "includes fg and bg when set" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, fg: "red", bg: "blue",
      )
      hash = el.to_h
      expect(hash[:fg]).to eq("red")
      expect(hash[:bg]).to eq("blue")
    end

    it "includes disabled when set" do
      el = described_class.new(
        role: :button, text: "OK", row: 0, col: 0, width: 4, height: 1, disabled: true,
      )
      expect(el.to_h).to have_key(:disabled)
      expect(el.to_h[:disabled]).to be true
    end
  end
end

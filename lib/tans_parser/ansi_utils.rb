# frozen_string_literal: true

module TansParser
  # Shared ANSI color constants and helpers.
  # Used by Screenshot, HtmlRenderer, and other color-aware renderers.
  module ANSIUtils
    ANSI_RGB = {
      "black" => [0x00, 0x00, 0x00],
      "red" => [0xAA, 0x00, 0x00],
      "green" => [0x00, 0xAA, 0x00],
      "yellow" => [0xAA, 0x55, 0x00],
      "blue" => [0x00, 0x00, 0xAA],
      "magenta" => [0xAA, 0x00, 0xAA],
      "cyan" => [0x00, 0xAA, 0xAA],
      "white" => [0xAA, 0xAA, 0xAA],
      "bright_black" => [0x55, 0x55, 0x55],
      "bright_red" => [0xFF, 0x55, 0x55],
      "bright_green" => [0x55, 0xFF, 0x55],
      "bright_yellow" => [0xFF, 0xFF, 0x55],
      "bright_blue" => [0x55, 0x55, 0xFF],
      "bright_magenta" => [0xFF, 0x55, 0xFF],
      "bright_cyan" => [0x55, 0xFF, 0xFF],
      "bright_white" => [0xFF, 0xFF, 0xFF],
    }.freeze

    CUBE = [0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF].freeze

    ANSI_INDEX = %w[
      black red green yellow blue magenta cyan white
      bright_black bright_red bright_green bright_yellow
      bright_blue bright_magenta bright_cyan bright_white
    ].freeze

    DEFAULT_FG = [0xC0, 0xC0, 0xC0].freeze
    DEFAULT_BG = [0x00, 0x00, 0x00].freeze

    def resolve_color(name, fallback)
      case name
      when "default"
        fallback
      when /^#([0-9a-fA-F]{6})$/
        [::Regexp.last_match(1)[0..1].to_i(16), ::Regexp.last_match(1)[2..3].to_i(16),
         ::Regexp.last_match(1)[4..5].to_i(16),]
      when /\Acolor(\d+)\z/
        xterm_256(::Regexp.last_match(1).to_i)
      when /\Abright_(.+)\z/
        ANSI_RGB[name] || fallback
      else # rubocop:disable Lint/DuplicateBranch
        ANSI_RGB[name] || fallback
      end
    end

    def xterm_256(index) # rubocop:disable Naming/VariableNumber
      if index < 16
        name = ANSI_INDEX[index]
        ANSI_RGB[name] || DEFAULT_FG
      elsif index < 232
        r = CUBE[((index - 16) / 36) % 6]
        g = CUBE[((index - 16) / 6) % 6]
        b = CUBE[(index - 16) % 6]
        [r, g, b]
      else
        v = 8 + ((index - 232) * 10)
        [v, v, v]
      end
    end

    def _dig(hash, *keys)
      keys.each do |k|
        return nil unless hash

        hash = hash[k] || hash[k.to_s]
      end
      hash
    end
  end
end

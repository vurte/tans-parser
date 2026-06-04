# frozen_string_literal: true

module TansParser
  class Error < StandardError; end
end

require_relative "tans_parser/version"
require_relative "tans_parser/ansi_parser"
require_relative "tans_parser/ansi_utils"
require_relative "tans_parser/element"
require_relative "tans_parser/selector"
require_relative "tans_parser/scoped_selector"
require_relative "tans_parser/state"

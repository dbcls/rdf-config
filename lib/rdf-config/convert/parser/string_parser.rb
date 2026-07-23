# frozen_string_literal: true

require 'parslet'

class RDFConfig
  class Convert
    class StringParser < Parslet::Parser
      rule(:escaped_char) do
        str('\\') >> any
      end

      rule(:double_quoted_string) do
        str('"') >>
          (
            escaped_char.as(:escaped) |
              (str('"').absent? >> any).as(:char)
          ).repeat.as(:chars) >>
          str('"') >>
          space?
      end

      rule(:single_quoted_string) do
        str("'") >>
          (
            escaped_char.as(:escaped) |
              (str("'").absent? >> any).as(:char)
          ).repeat.as(:chars) >>
          str("'") >>
          space?
      end

      rule(:quoted_string) do
        (double_quoted_string | single_quoted_string).as(:string)
      end

      rule(:space?) { match('\s').repeat }

      root :quoted_string
    end

    class StringTransform < Parslet::Transform
      rule(chars: subtree(:chars)) do
        chars.map do |char|
          if char.is_a?(Hash) && char[:escaped]
            escaped = char[:escaped]
            case escaped
            when '\\' then '\\'
            when '"'  then '"'
            when "'"  then "'"
            when 'n'  then "\n"
            when 't'  then "\t"
            else escaped
            end
          elsif char.is_a?(Hash) && char[:char]
            char[:char]
          else
            char.to_s
          end
        end.join
      end
    end
  end
end

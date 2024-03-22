require 'parslet'

class RDFConfig
  class Convert
    class MethodParser < Parslet::Parser
      rule(:space) { match('\s').repeat(1) }
      rule(:space?) { space.maybe }
      rule(:comma) { str(',') }
      rule(:array_left) { space.repeat >> str('[') >> space.repeat }
      rule(:array_sep) { space.repeat >> comma >> space.repeat }
      rule(:array_right) { space.repeat >> str(']') >> space.repeat }

      rule(:method_name) {
        (
          match('[a-z]').repeat(1) >>
            (str('_') >> match('[a-z]').repeat(1)).repeat
        ).as(:method_name_) >> space?
      }

      rule(:dquot_string) {
        str('"') >>
          ((str('"').absent? >> any).repeat) >>
          str('"') >> space?
      }

      rule(:squot_string) {
        str("'") >>
          ((str("'").absent? >> any).repeat) >>
          str("'") >> space?
      }

      rule(:element) { (dquot_string | squot_string) >> space.maybe }

      rule(:array) do
        array_left >>
          element >> (array_sep >> element).repeat >>
        array_right
      end

      rule(:regexp) {
        str('/') >>
          (str('/').absent? >> any).repeat(1) >>
          str('/') >> (match('[a-z]').repeat)
      }

      rule(:variable_name) do
        str('$') >> (match('[a-z_0-9]').repeat)
      end

      rule(:arg) { (dquot_string | squot_string | array | regexp | variable_name).as(:arg_) }
      rule(:args) {
        str('(') >>
          (
            arg >> (str(',') >> space? >> arg).repeat
          ).as(:args_) >>
          str(')')
      }

      rule(:method) {
        method_name >> args.maybe
      }

      root(:method)
    end
  end
end

require 'rdf-config/schema/chart/svg_utils'
require 'rdf-config/schema/chart/table/constant'

class RDFConfig
  class Schema
    class Chart
      class Table
        class ElementGenerator
          include Constant
          include SvgUtils

          class << self
            def calc_text_width(text)
              text_chars = text.to_s.chars

              wide_width_chars = text_chars.select { |char| %w[C D Q R S].include?(char) }
              narrow_width_chars = text_chars.select { |char| %w[f i j l t :].include?(char) }

              (Constant::FONT_SIZE * 0.7) * wide_width_chars.size
              + (Constant::FONT_SIZE * 0.2) * narrow_width_chars.size
              + (Constant::FONT_SIZE * 0.5) * (text_chars.size - wide_width_chars.size - narrow_width_chars.size)
            end
          end

          def initialize(xpos, ypos, table_width, opts = {})
            @xpos = xpos
            @ypos = ypos
            @table_width = table_width
            @opts = opts
          end

          def name_x_position
            @xpos + TABLE_PADDING_LEFT
          end

          def text_y_position(rect_height, font_size)
            @ypos + (rect_height - 3) - (rect_height - font_size) / 2
          end

          def text_width(text)
            self.class.calc_text_width(text)
          end

          def subject_rdf_type_text(subject)
            if subject.types.size > 1
              "#{subject.types.first}, ..."
            else
              subject.types.first
            end
          end
        end
      end
    end
  end
end

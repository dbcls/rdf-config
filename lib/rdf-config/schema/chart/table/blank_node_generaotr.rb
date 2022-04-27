require 'rdf-config/schema/chart/table/element_generator'

class RDFConfig
  class Schema
    class Chart
      class Table
        class BlankNodeGenerator < TableGenerator
          def initialize(subject, xpos, ypos, table_width, opts = {})
            super
          end

          private

          def generate_subject
            g = REXML::Element.new('g')
            g.add_element(generate_name)
            g.add_element(generate_rdf_type)

            g
          end

          def generate_name
            text = REXML::Element.new('text')
            text.add_attribute_by_hash(
              x: name_x_position - 5,
              y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
              class: text_element_class
            )
            text.add_text(name)

            text
          end

          def generate_rdf_type
            text = REXML::Element.new('text')
            text.add_attribute_by_hash(
              x: @table_x + @table_width,
              y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
              'text-anchor' => 'end',
              class: text_element_class
            )
            text.add_text(rdf_type)

            text
          end

          def generate_outer_frame
            path = REXML::Element.new('path')
            path.add_attribute_by_hash(
              d: outer_frame_path_d_attrs.join(' '),
              class: 'blank-node-object'
            )

            path
          end

          def outer_frame_path_d_attrs
            x1 = @xpos
            y1 = @ypos
            x2 = x1 + @table_width
            y2 = SvgGenerator.current_y
            horizontal_line_width = @table_width - (SUBJECT_HEIGHT - BEZIER_ADJ) * 2
            vertical_line_height = (y2 - y1) - (SUBJECT_HEIGHT - BEZIER_ADJ) - (OBJECT_HEIGHT - BEZIER_ADJ)

            [
              "M #{x1},#{y1 + (SUBJECT_HEIGHT - BEZIER_ADJ)}",
              "Q #{x1},#{y1} #{x1 + (SUBJECT_HEIGHT - BEZIER_ADJ)},#{y1}",
              "h #{horizontal_line_width}",
              "Q #{x2},#{y1} #{x2},#{y1 + (SUBJECT_HEIGHT - BEZIER_ADJ)}",
              "v #{vertical_line_height}",
              "Q #{x2},#{y2} #{x2 - (OBJECT_HEIGHT - BEZIER_ADJ)},#{y2}",
              "h -#{horizontal_line_width}",
              "Q #{x1},#{y2} #{x1},#{y2 - (OBJECT_HEIGHT - BEZIER_ADJ)}",
              "v -#{vertical_line_height}"
            ]
          end

          def text_element_class
            'object-text'
          end

          def name
            @subject.blank_node? ? @subject.bnode_name : @subject.name
          end

          def rdf_type
            @subject.type
          end
        end
      end
    end
  end
end

require 'rdf-config/schema/chart/table/element_generator'

class RDFConfig
  class Schema
    class Chart
      class Table
        class SubjectGenerator < ElementGenerator
          def initialize(subject, xpos, ypos, table_width, opts = {})
            super(xpos, ypos, table_width, opts)

            @subject = subject
            @table_xpos = opts[:table_xpos]
          end

          def generate
            g = REXML::Element.new('g')
            g.add_element(generate_container)
            g.add_element(generate_name)
            g.add_element(generate_rdf_type)

            g
          end

          def generate_container
            path = REXML::Element.new('path')

            path.add_attribute_by_hash(
              d: rounded_corners_d_attrs.join(' '),
              class: 'subject-container'
            )

            path
          end

          def generate_name
            text = REXML::Element.new('text')
            text.add_attribute_by_hash(
              x: name_x_position,
              y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
              class: text_css_class
            )
            text.add_text(name)

            text
          end

          def generate_rdf_type
            text = REXML::Element.new('text')
            text.add_attribute_by_hash(
              x: @table_xpos + @table_width - TABLE_PADDING_RIGHT,
              y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
              'text-anchor' => 'end',
              class: 'subject-type'
            )
            text.add_text(subject_rdf_type_text(@subject))

            text
          end

          def name
            @subject.blank_node? ? @subject.bnode_name : @subject.name
          end

          def text_css_class
            'subject-text'
          end

          def rounded_corners_d_attrs
            [
              "M #{@xpos},#{@ypos + SUBJECT_HEIGHT}",
              "v -#{BEZIER_ADJ}",
              "q 0,-#{SUBJECT_HEIGHT - BEZIER_ADJ} #{SUBJECT_HEIGHT - BEZIER_ADJ},-#{SUBJECT_HEIGHT - BEZIER_ADJ}",
              "h #{@table_width - (SUBJECT_HEIGHT - BEZIER_ADJ) * 2}",
              "q #{SUBJECT_HEIGHT - BEZIER_ADJ},0 #{SUBJECT_HEIGHT - BEZIER_ADJ},#{SUBJECT_HEIGHT - BEZIER_ADJ}",
              "v #{BEZIER_ADJ}"
            ]
          end

          def rectangle_d_attrs
            [
              "M #{@xpos},#{@ypos}",
              "h #{@table_width}",
              "v #{SUBJECT_HEIGHT}",
              "h -#{@table_width}",
              "v -#{SUBJECT_HEIGHT}"
            ]
          end
        end
      end
    end
  end
end

require 'rdf-config/schema/chart/svg_utils'
require 'rdf-config/schema/chart/table/svg_generator'
require 'rdf-config/schema/chart/table/element_generator'
require 'rdf-config/schema/chart/table/subject_generator'
require 'rdf-config/schema/chart/table/object_generator'

class RDFConfig
  class Schema
    class Chart
      class Table
        class TableGenerator < ElementGenerator
          def initialize(subject, xpos, ypos, table_width, opts = {})
            super(xpos, ypos, table_width, opts)
            @subject = subject
            @objects = subject.objects(reject_rdf_type: true)
            @table_x = opts[:table_x]
            @table_y = opts[:table_y]
          end

          def generate
            # Generate subject element
            subject_element = generate_subject
            SvgGenerator.move_to_first_object

            # Generate object elements
            object_elements = []
            @objects.each do |object|
              object_elements << if object.blank_node?
                                   SvgGenerator.generate_table(object.as_subject)
                                 else
                                   SvgGenerator.generate_object(object, is_last: @objects.last == object)
                                 end
            end

            # wrapper element for table
            table_g = REXML::Element.new('g')

            # generate outer frame
            table_g.add_element(generate_outer_frame)

            # add object elements
            object_elements.each do |element|
              table_g.add_element(element)
            end

            # add subject element
            table_g.add_element(subject_element)

            table_g
          end

          private

          def generate_subject
            SvgGenerator.generate_subject(@subject)
          end

          def generate_outer_frame
            rect = REXML::Element.new('rect')
            attrs = {
              x: @table_x,
              y: @table_y,
              width: @table_width,
              height: SvgGenerator.current_y - @table_y - OBJECT_MARGIN + SUBJECT_WRAPPER_PADDING,
              class: 'subject-wrapper'
            }
            rect.add_attribute_by_hash(attrs)

            rect
          end
        end
      end
    end
  end
end

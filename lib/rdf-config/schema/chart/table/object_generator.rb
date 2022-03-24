require 'rdf-config/schema/chart/table/svg_generator'
require 'rdf-config/schema/chart/table/element_generator'
require 'rdf-config/schema/chart/table/constant'

class RDFConfig
  class Schema
    class Chart
      class Table
        class ObjectGenerator < ElementGenerator
          def initialize(object, xpos, ypos, table_width, opts = {})
            super(xpos, ypos, table_width, opts)
            @bnode_ident = opts[:bnode_ident] || 0
            @xpos += Constant::SUBJECT_WRAPPER_PADDING if in_bnode?
            @object = object
            @is_last = opts[:is_last]
          end

          def generate
            g = REXML::Element.new('g')
            rect = REXML::Element.new('rect')
            rect.add_attribute_by_hash(
              x: @xpos, y: @ypos,
              width: width,
              height: OBJECT_HEIGHT,
              class: area_css_class
            )
            g.add_element(rect)
            g.add_element(generate_name)

            g
          end

          def generate_name
            text = REXML::Element.new('text')
            text.add_attribute_by_hash(
              x: name_x_position,
              y: text_y_position(OBJECT_HEIGHT, FONT_SIZE),
              class: text_css_class
            )
            text.add_text(element_text)

            text
          end

          def element_text
            if @object.blank_node?
              @object.value.bnode_name
            elsif subject?
              case @object
              when Model::Subject
                subject = @object
                subject_name = subject.name
              when Model::ValueList
                subject = @object.value.select { |value| value.is_a?(Model::Subject) }.first
                subject_name = @object.value[0..1].map(&:name).join(', ')
                subject_name = "#{subject_name}, ..." if @object.value.size > 2
              end
              if subject
                "#{subject.as_object_name} (#{subject_name})"
              else
                ''
              end
            else
              @object.name
            end
          end

          def area_css_class
            return 'subject-area black-stroke' if subject?

            case @object
            when Model::Subject
              'resource black-stroke'
            when Model::URI
              'resource black-stroke'
            when Model::Literal
              'literal black-stroke'
            when Model::BlankNode
              'blank-node'
            when Model::ValueList
              if @object.value.first.is_a?(Model::URI)
                'resource black-stroke'
              else
                'literal black-stroke'
              end
            else
              'unknown black-stroke'
            end
          end

          def text_css_class
            if subject?
              'text subject'
            else
              'text'
            end
          end

          def width
            object_width = @table_width - SUBJECT_WRAPPER_PADDING * 2
            object_width -= (SUBJECT_WRAPPER_PADDING + @bnode_ident * BLANK_NODE_LEFT_MARGIN) if in_bnode?

            object_width
          end

          def in_bnode?
            SvgGenerator.in_bnode?
          end

          def subject?
            @object.is_a?(Model::Subject) ||
              (@object.is_a?(Model::ValueList) && !@object.value.select { |value| value.is_a?(Model::Subject) }.empty?)
          end
        end
      end
    end
  end
end

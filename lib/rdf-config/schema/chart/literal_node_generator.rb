require 'rdf-config/schema/chart/node_element'

class RDFConfig
  class Schema
    class Chart
      class LiteralNodeGenerator
        include NodeElement

        def initialize(node, pos)
          @node = node
          @pos = pos
        end

        def generate
          literal_elements
        end

        private

        def literal_elements
          wrapper = REXML::Element.new('g')

          wrapper.add_element(rect_element)
          wrapper.add_element(name_type_rect_element)
          wrapper.add_element(value_element)
          wrapper.add_element(name_element)
          wrapper.add_element(type_element)

          [wrapper]
        end

        def rect_element
          rect = REXML::Element.new('rect')
          rect.add_attribute_by_hash(
            x: @pos.x,
            y: @pos.y,
            width: RECT_WIDTH,
            height: RECT_HEIGHT,
            class: 'st9'
          )

          rect
        end

        def name_type_rect_element
          paths = ["#{@pos.x},#{@pos.y + LITERAL_TYPE_RECT_HEIGHT}"]
          paths << "#{@pos.x},#{@pos.y}"
          paths << "#{@pos.x + RECT_WIDTH},#{@pos.y}"
          paths << "#{@pos.x + RECT_WIDTH},#{@pos.y + LITERAL_TYPE_RECT_HEIGHT}"

          name_type_area = REXML::Element.new('polyline')
          name_type_area.add_attribute_by_hash(
            points: paths.join(' '),
            class: 'st2'
          )

          name_type_area
        end

        def value_element
          value = REXML::Element.new('text')
          value.add_attribute_by_hash(
            x: @pos.x + LITERAL_MARGIN_LEFT,
            y: @pos.y + LITERAL_TYPE_RECT_HEIGHT + (RECT_HEIGHT - LITERAL_TYPE_RECT_HEIGHT) / 2,
            class: 'st3 st4',
            'dominant-baseline' => 'middle'
          )
          value.add_text(@node.value.to_s)

          wrapper = REXML::Element.new('g')
          wrapper.add_element(value)

          wrapper
        end

        def name_element
          name = REXML::Element.new('text')
          name.add_attribute_by_hash(
            x: @pos.x + LITERAL_MARGIN_LEFT,
            y: @pos.y + LITERAL_TYPE_RECT_HEIGHT / 2,
            class: 'st5 st6 st7',
            'dominant-baseline' => 'middle'
          )
          name.add_text(@node.name.to_s)

          wrapper = REXML::Element.new('g')
          wrapper.add_element(name)

          wrapper
        end

        def type_element
          type = REXML::Element.new('text')
          type.add_attribute_by_hash(
            x: @pos.x + RECT_WIDTH - LITERAL_MARGIN_RIGHT,
            y: @pos.y + LITERAL_TYPE_RECT_HEIGHT / 2,
            class: 'st8 st6 st7',
            'text-anchor' => 'end',
            'dominant-baseline' => 'middle'
          )
          type.add_text(@node.type.to_s)

          wrapper = REXML::Element.new('g')
          wrapper.add_element(type)

          wrapper
        end
      end
    end
  end
end

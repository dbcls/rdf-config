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
          inner_texts = [@node.name, @node.value]

          object_literal_elements(@pos, inner_texts, @node.type)
        end

        private

        def object_literal_elements(pos, inner_texts, data_type = :String)
          g_wrapper_element = REXML::Element.new('g')
          literal_rect_elements(pos, data_type).each do |element|
            g_wrapper_element.add_element(element)
          end

          g_wrapper_element.add_element(text_g_element(pos, inner_texts))

          [g_wrapper_element]
        end

        def literal_rect_elements(pos, data_type = :String)
          g = REXML::Element.new('g')
          rect = REXML::Element.new('rect')
          rect_type = REXML::Element.new('rect')
          g_type = REXML::Element.new('g')
          text_type = REXML::Element.new('text')

          rect.add_attribute_by_hash(literal_rect_elem_opts(pos))
          g.add_element(rect)

          rect_type.add_attribute_by_hash(data_type_rect_opts(pos))

          g_type_opts = {
              transform: "translate(-0.5 -0.5) rotate(-90 #{pos.x + 170} #{pos.y + 25})"
          }
          g_type.add_attribute_by_hash(g_type_opts)

          text_type.add_attribute_by_hash(data_type_string_opts(pos))
          text_type.add_text(data_type.to_s)

          g_type.add_element(text_type)

          [g, rect_type, g_type]
        end

        def literal_rect_elem_opts(pos)
          {
              x: pos.x,
              y: pos.y,
              width: RECT_WIDTH - LITERAL_TYPE_RECT_HEIGHT,
              height: RECT_HEIGHT,
              fill: LITERAL_RECT_BG,
              stroke: STROKE_COLOR,
              'stroke-width' => STROKE_WIDTH,
              'pointer-events' => 'all'
          }
        end

        def data_type_rect_opts(pos)
          text_x = pos.x + RECT_WIDTH - (LITERAL_TYPE_RECT_WIDTH + LITERAL_TYPE_RECT_HEIGHT) / 2
          text_y = pos.y + (RECT_HEIGHT - LITERAL_TYPE_RECT_HEIGHT) / 2
          rotate_x = pos.x + RECT_WIDTH - LITERAL_TYPE_RECT_HEIGHT / 2
          rotate_y = pos.y + RECT_HEIGHT / 2
          {
              x: text_x,
              y: text_y,
              width: LITERAL_TYPE_RECT_WIDTH,
              height: LITERAL_TYPE_RECT_HEIGHT,
              fill: '#000000',
              stroke: STROKE_COLOR,
              'stroke-width' => STROKE_WIDTH,
              transform: "rotate(-90,#{rotate_x},#{rotate_y})",
              'pointer-events' => 'all'
          }
        end

        def data_type_string_opts(pos)
          {
              x: pos.x + 170,
              y: pos.y + 28,
              fill: '#ffffff',
              'font-family' => FONT_FAMILY,
              'font-size' => FONT_SIZE,
              'font-style' => 'italic',
              'text-anchor' => 'middle',
              'font-weight' => 'bold'
          }
        end
      end
    end
  end
end

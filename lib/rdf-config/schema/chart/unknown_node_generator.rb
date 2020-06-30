require 'rdf-config/schema/chart/node_element'

class RDFConfig
  class Schema
    class Chart
      class UnknownNodeGenerator
        include NodeElement

        def initialize(node, pos)
          @node = node
          @pos = pos
        end

        def generate
          unknown_object_elements
        end

        private

        def unknown_object_elements
          g_wrapper_element = REXML::Element.new('g')
          rect_element = REXML::Element.new('rect')
          rect_element.add_attribute_by_hash(unknown_literal_rect_opts)
          g_wrapper_element.add_element(rect_element)
          g_wrapper_element.add_element(text_g_element(@pos, inner_texts))

          [g_wrapper_element]
        end

        def unknown_literal_rect_opts
          {
            x: @pos.x,
            y: @pos.y,
            width: RECT_WIDTH,
            height: RECT_HEIGHT,
            fill: UNKNOWN_RECT_BG,
            stroke: STROKE_COLOR,
            'stroke-width' => STROKE_WIDTH,
            'pointer-events' => 'all'
          }
        end

        def inner_texts
          [@node.name]
        end
      end
    end
  end
end

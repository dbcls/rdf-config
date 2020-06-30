require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      class BlankNodeGenerator
        include Constant

        def initialize(pos)
          @pos = pos
        end

        def generate
          g = REXML::Element.new('g')

          ellipse = REXML::Element.new('ellipse')
          ellipse.add_attribute_by_hash(ellipse_opts)

          g.add_element(ellipse)

          [g]
        end

        private

        def ellipse_opts
          {
            cx: @pos.x + BNODE_RADIUS,
            cy: @pos.y + BNODE_RADIUS + (RECT_HEIGHT - BNODE_RADIUS * 2) / 2,
            rx: BNODE_RADIUS,
            ry: BNODE_RADIUS,
            fill: BNODE_CIRCLE_BG,
            stroke: STROKE_COLOR,
            'stroke-dasharray' => '3 3',
            'pointer-events' => 'all'
          }
        end
      end
    end
  end
end
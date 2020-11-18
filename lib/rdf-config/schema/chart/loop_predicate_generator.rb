require 'rdf-config/schema/chart/predicate_generator'
require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      class LoopPredicateGenerator < PredicateGenerator
        include Constant

        SUBJECT_VINTERVAL = 20

        def initialize(predicate, pos)
          @predicate = predicate
          @pos = ArrowPosition.new(pos.x2 - PREDICATE_AREA_WIDTH + VLINE_INTERVAL, pos.y2,
                                   pos.x1 - RECT_WIDTH + SUBJECT_VINTERVAL, pos.y1 + RECT_HEIGHT / 2 + ARROW_END_MARGIN)
        end

        private

        def generate_arrow
          g = REXML::Element.new('g')
          g.add_attribute('transform', "rotate(270, #{@pos.x2}, #{@pos.y2})")

          polygon = REXML::Element.new('polygon')
          polygon.add_attribute_by_hash(arrow_opts)
          g.add_element(polygon)

          [g]
        end

        def line_opts
          {
            class: @predicate.rdf_type? ? 'st11' : 'st12',
            points: "#{@pos.x1},#{@pos.y1 - (RECT_HEIGHT + MARGIN_RECT)} #{@pos.x1},#{@pos.y1} #{@pos.x2},#{@pos.y1} #{@pos.x2},#{@pos.y2}"
          }
        end

        def text_opts
          {
            class: 'st6 st4',
            transform: "matrix(1 0 0 1 #{@pos.x2 + TEXT_MARGIN_X} #{@pos.y1 - TEXT_MARGIN_Y})"
          }
        end
      end
    end
  end
end

class RDFConfig
  class Schema
    class Chart
      class PredicateGenerator
        VLINE_INTERVAL = 20
        ARROW_END_MARGIN = 5
        TEXT_MARGIN_X = 10
        TEXT_MARGIN_Y = 5

        def initialize(predicate, pos)
          @predicate = predicate
          @pos = ArrowPosition.new(pos.x1, pos.y1, pos.x2 - ARROW_END_MARGIN, pos.y2)
        end

        def generate
          elements = []
          elements += generate_line
          elements += generate_arrow
          elements += generate_text

          elements
        end

        private

        def generate_line
          polyline = REXML::Element.new('polyline')
          polyline.add_attribute_by_hash(line_opts)

          [polyline]
        end

        def generate_arrow
          polygon = REXML::Element.new('polygon')
          polygon.add_attribute_by_hash(arrow_opts)

          [polygon]
        end

        def generate_text
          predicate_text = if @predicate.cardinality
                             "#{@predicate.uri} #{@predicate.cardinality.label}"
                           else
                             @predicate.uri
                           end

          text = REXML::Element.new('text')
          text.add_attribute_by_hash(text_opts)
          text.add_text(predicate_text)

          [text]
        end

        def line_opts
          {
            class: @predicate.rdf_type? ? 'st11' : 'st12',
            points: "#{@pos.x1},#{@pos.y1} #{@pos.x1 + VLINE_INTERVAL},#{@pos.y1} #{@pos.x1 + VLINE_INTERVAL},#{@pos.y2} #{@pos.x2},#{@pos.y2}"
          }
        end

        def arrow_opts
          points = []

          x = (@pos.x2 - 4.7).round(1)
          y = (@pos.y2 + 5.7).round(1)
          points << "#{x},#{y}"

          x = (x - 0.9).round(1)
          y = (y - 1.0).round(1)
          points << "#{x},#{y}"

          x = (x + 5.0).round(1)
          y = (y - 4.7).round(1)
          points << "#{x},#{y}"

          x = (x - 5.0).round(1)
          y = (y - 4.7).round(1)
          points << "#{x},#{y}"

          x = (x + 0.9).round(1)
          y = (y - 1.0).round(1)
          points << "#{x},#{y}"

          x = (x + 6.2).round(1)
          y = (y + 5.7).round(1)
          points << "#{x},#{y}"

          { points: points.join(' ') }
        end

        def text_opts
          {
            class: 'st6 st4',
            transform: "matrix(1 0 0 1 #{@pos.x1 + VLINE_INTERVAL + TEXT_MARGIN_X} #{@pos.y2 - TEXT_MARGIN_Y})"
          }
        end

      end
    end
  end
end

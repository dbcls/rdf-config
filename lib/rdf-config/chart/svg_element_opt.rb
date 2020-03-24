class RDFConfig
  class Chart
    class Schema
      module SVGElementOpt
        FONT_FAMILY = 'Helvetica'.freeze
        FONT_SIZE = '12px'.freeze
        RECT_WIDTH = 180.freeze
        RECT_HEIGHT = 50.freeze
        MARGIN_RECT = 30.freeze

        PREDICATE_AREA_WIDTH = 240.freeze
        PREDICATE_TRIANGLE_BASE_LEN = 10.freeze
        PREDICATE_TRIANGLE_HEIGHT = 13.freeze

        RDF_TYPE_RECT_BG = '#fff4c3'.freeze
        URI_INSTANCE_RECT_BG = '#ffce9f'.freeze
        URI_RECT_RADIUS = 7.5.freeze

        LITERAL_RECT_BG = '#f8cecc'.freeze
        LITERAL_TYPE_RECT_WIDTH = RECT_HEIGHT
        LITERAL_TYPE_RECT_HEIGHT = 20.freeze

        UNKNOWN_RECT_BG = '#e0e0e0'.freeze

        BNODE_CIRCLE_BG = '#f2f2e9'.freeze
        BNODE_RADIUS = 20.freeze

        STROKE_WIDTH = 3.freeze
        STROKE_COLOR = '#000000'.freeze

        def uri_rect_elem_opts(pos, class_or_instance)
          case class_or_instance
          when :class
            fill = RDF_TYPE_RECT_BG
          when :instance
            fill = URI_INSTANCE_RECT_BG
          end

          {
              x: pos.x,
              y: pos.y,
              width: RECT_WIDTH,
              height: RECT_HEIGHT,
              rx: URI_RECT_RADIUS,
              ry: URI_RECT_RADIUS,
              fill: fill,
              stroke: STROKE_COLOR,
              'stroke-width' => STROKE_WIDTH,
              'pointer-events' => 'all'
          }
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

        def unknown_literal_rect_opts(pos)
          {
              x: pos.x,
              y: pos.y,
              width: RECT_WIDTH,
              height: RECT_HEIGHT,
              fill: UNKNOWN_RECT_BG,
              stroke: STROKE_COLOR,
              'stroke-width' => STROKE_WIDTH,
              'pointer-events' => 'all'
          }
        end

        def blank_node_ellipse_opts(pos)
          {
              cx: pos.x + BNODE_RADIUS,
              cy: pos.y + BNODE_RADIUS,
              rx: BNODE_RADIUS,
              ry: BNODE_RADIUS,
              fill: BNODE_CIRCLE_BG,
              stroke: STROKE_COLOR,
              'stroke-dasharray' => '3 3',
              'pointer-events' => 'all'
          }
        end

        def predicate_arrow_text_pos(pos)
          Point.new(pos.x1 + (pos.x2 - pos.x1) / 2, pos.y1 + (pos.y2 - pos.y1) / 2)
        end

        def predicate_arrow_opts(pos, type)
          opts = {}

          x_dist = (pos.x2 - pos.x1).abs.to_f
          y_dist = (pos.y2 - pos.y1).abs.to_f
          l_dist = distance(pos.x1, pos.y1, pos.x2, pos.y2)
          sin = y_dist / l_dist
          cos = x_dist / l_dist

          x3 = pos.x2 - cos * PREDICATE_TRIANGLE_HEIGHT
          y3 = pos.y2 - sin * PREDICATE_TRIANGLE_HEIGHT
          x4 = x3 - PREDICATE_TRIANGLE_BASE_LEN / 2 * sin
          y4 = y3 + PREDICATE_TRIANGLE_BASE_LEN / 2 * cos
          x5 = x3 + PREDICATE_TRIANGLE_BASE_LEN / 2 * sin
          y5 = y3 - PREDICATE_TRIANGLE_BASE_LEN / 2 * cos

          text_pos = predicate_arrow_text_pos(pos)

          path_line_d = "M #{pos.x1} #{pos.y1} L #{x3} #{y3}"
          path_triangle_d = "M #{pos.x2 - 2} #{pos.y2} L #{x4} #{y4} L #{x5} #{y5} Z"

          case type
          when :rdf_type
            opts[:line] = {
                d: path_line_d,
                fill: 'none',
                stroke: '#000000',
                'stroke-width' => '3',
                'stroke-miterlimit' => '10',
                'stroke-dasharray' => '9 9',
                'pointer-events' => 'stroke'
            }
            opts[:triangle] = {
                d: path_triangle_d,
                fill: 'none',
                stroke: '#000000',
                'stroke-width' => STROKE_WIDTH,
                'stroke-miterlimit' => '10',
                'pointer-events' => 'all'
            }
          when :predicate
            opts[:line] = {
                d: path_line_d,
                fill: 'none',
                stroke: '#000000',
                'stroke-width' => STROKE_WIDTH,
                'stroke-miterlimit' => '10',
                'pointer-events' => 'stroke'
            }
            opts[:triangle] = {
                d: path_triangle_d,
                fill: '#000000',
                stroke: '#000000',
                'stroke-width' => STROKE_WIDTH,
                'stroke-miterlimit' => '10',
                'pointer-events' => 'all'
            }
          end

          opts[:text] = {
              x: text_pos.x,
              y: text_pos.y,
              fill: '#000000',
              'font-family' => FONT_FAMILY,
              'font-size' => FONT_SIZE,
              'text-anchor' => 'middle',
              'font-weight' => 'bold'
          }

          opts
        end


      end
    end
  end
end

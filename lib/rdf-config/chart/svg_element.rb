class RDFConfig
  class Chart
    class Schema
      module SVGElement
        include SVGElementOpt

        def uri_elements(pos, inner_texts, type = :instance)
          g_wrapper_element = REXML::Element.new('g')

          rect_element = REXML::Element.new('rect')
          rect_element.add_attribute_by_hash(uri_rect_elem_opts(pos, type))
          g_wrapper_element.add_element(rect_element)
          g_wrapper_element.add_element(text_g_element(pos, inner_texts))

          [g_wrapper_element]
        end

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

        def unknown_object_elements(pos, inner_texts)
          g_wrapper_element = REXML::Element.new('g')

          rect_element = REXML::Element.new('rect')
          rect_element.add_attribute_by_hash(unknown_literal_rect_opts(pos))
          g_wrapper_element.add_element(rect_element)
          g_wrapper_element.add_element(text_g_element(pos, inner_texts))

          [g_wrapper_element]
        end

        def blank_node_elements(pos)
          g = REXML::Element.new('g')

          ellipse = REXML::Element.new('ellipse')
          ellipse.add_attribute_by_hash(blank_node_ellipse_opts(pos))

          g.add_element(ellipse)

          [g]
        end

        def predicate_arrow_elements(pos, type, legend = '')
          g_wrapper = REXML::Element.new('g')
          path_line = REXML::Element.new('path')
          path_triangle = REXML::Element.new('path')
          g_text = REXML::Element.new('g')
          switch = REXML::Element.new('switch')
          text = REXML::Element.new('text')

          opts = predicate_arrow_opts(pos, type)
          path_line.add_attribute_by_hash(opts[:line])
          path_triangle.add_attribute_by_hash(opts[:triangle])

          g_text_opts = {
              transform: 'translate(-0.5 -0.5)'
          }
          g_text.add_attribute_by_hash(g_text_opts)

          text.add_attribute_by_hash(opts[:text])
          text.add_text(legend.to_s)

          text_pos = predicate_arrow_text_pos(pos)
          div_opts = {
              width: '1px',
              padding_top: "#{text_pos.y}px",
              margin_left: "#{text_pos.x}px"
          }
          text_opts = {
              'font-weight' => 'bold',
              'background-color' => '#ffffff'
          }
          switch.add_element(
              foreign_object_element(legend.to_s, div_opts, text_opts)
          )
          switch.add_element(text)

          g_wrapper.add_element(path_line)
          g_wrapper.add_element(path_triangle)
          g_wrapper.add_element(switch)

          [g_wrapper]
        end

        def foreign_object_element(inner_texts, div_opts = {}, text_opts = {})
          foreign_object = REXML::Element.new('foreignObject')
          foreign_object_style = {
              overflow: 'visible',
              'text-align' => 'left'
          }
          foreign_object_opts = {
              style: style_value_by_hash(foreign_object_style),
              'pointer-events' => 'none',
              width: '100%',
              height: '100%',
              requiredFeatures: 'http://www.w3.org/TR/SVG11/feature#Extensibility'
          }
          foreign_object.add_attribute_by_hash(foreign_object_opts)

          div_f_element = REXML::Element.new('div')
          div_f_style_opts = {
              display: 'flex',
              'align-items' => 'unsafe center',
              'justify-content' => 'unsafe center',
              width: div_opts[:width],
              height: '1px',
              'padding-top' => div_opts[:padding_top],
              'margin-left' => div_opts[:margin_left]
          }
          div_f_elem_opts = {
              xmlns: 'http://www.w3.org/1999/xhtml',
              style: style_value_by_hash(div_f_style_opts)
          }
          div_f_element.add_attribute_by_hash(div_f_elem_opts)

          div_s_element = REXML::Element.new('div')
          div_s_element.add_attribute('style', 'box-sizing: border-box; font-size: 0; text-align: center;')

          div_t_element = REXML::Element.new('div')
          div_t_style_opts = {
              display: 'inline-block',
              'font-size' => FONT_SIZE,
              'font-family' => FONT_FAMILY,
              color: '#000000',
              'line-height' => '1.2',
              'pointer-events' => 'all',
              'white-space' => 'normal',
              'word-wrap' => 'normal'
          }
          text_opts.each do |name, value|
            div_t_style_opts[name.to_s] = value
          end

          div_t_element.add_attribute('style', style_value_by_hash(div_t_style_opts))
          case inner_texts
          when String
            div_t_element.add_text(inner_texts)
          when Array
            inner_texts.each do |text|
              div = REXML::Element.new('div')
              div.add_text(text.to_s)
              div.add_element(REXML::Element.new('br'))
              div_t_element.add_element(div)
            end
          end

          div_s_element.add_element(div_t_element)
          div_f_element.add_element(div_s_element)
          foreign_object.add_element(div_f_element)

          foreign_object
        end

        def rect_text_element(pos, inner_texts)
          element = REXML::Element.new('text')
          elem_opts = {
              x: pos.x + RECT_WIDTH / 2,
              y: pos.y + MARGIN_RECT - 1,
              fill: '#000000',
              'font-family' => FONT_FAMILY,
              'font-size' => FONT_SIZE,
              'text-anchor' => 'middle'
          }
          element.add_attribute_by_hash(elem_opts)

          case inner_texts
          when String
            element.add_text(inner_texts)
          when Array
            element.add_text(inner_texts.join(' '))
          end

          element
        end

        def text_g_element(pos, inner_texts)
          g = REXML::Element.new('g')
          g.add_attribute('transform', 'translate(-0.5 -0.5)')

          switch = REXML::Element.new('switch')

          div_opts = {
              width: "#{RECT_WIDTH - 2}px",
              padding_top: "#{pos.y + RECT_HEIGHT / 2}px",
              margin_left: "#{pos.x + 1}px"
          }
          text_opts = {}
          switch.add_element(
              foreign_object_element(inner_texts, div_opts, text_opts)
          )
          switch.add_element(rect_text_element(pos, inner_texts))

          g.add_element(switch)

          g
        end

        def svg_element
          svg = REXML::Element.new('svg')
          svg.add_attribute('xmlns', 'http://www.w3.org/2000/svg')
          svg.add_attribute('style', 'background-color: rgb(255, 255, 255);')

          svg
        end

      end
    end
  end
end

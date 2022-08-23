require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      module NodeElement
        include Constant

        def uri_elements(pos, inner_texts, type = :instance)
          g_wrapper_element = REXML::Element.new('g')

          rect_element = REXML::Element.new('rect')
          rect_element.add_attribute_by_hash(uri_rect_elem_opts(pos, type))
          g_wrapper_element.add_element(rect_element)
          g_wrapper_element.add_element(text_g_element(pos, inner_texts))

          [g_wrapper_element]
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

        private

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

        def style_value_by_hash(hash)
          hash.map { |name, value| "#{name}: #{value}" }.join('; ')
        end
      end
    end
  end
end

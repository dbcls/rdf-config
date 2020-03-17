class RDFConfig

  class Chart
    def initialize(model)
      @model = model
    end

    class Senbero < Chart
      def initialize(model)
        super
      end

      def generate
        @model.subjects.each do |subject|
          subject_class = @model.subject_type_map[subject]
          puts "#{subject} (#{subject_class})"
          predicates = @model.predicates[subject]
          predicates.each_with_index do |predicate, i|
            if i < predicates.size - 1
              puts "    |-- #{predicate}"
            else
              puts "    `-- #{predicate}"
            end
            objects = @model.objects[subject][predicate]
            objects.each_with_index do |object, j|
              object_label_value = @model.object_label_map[subject][object]
              object_label = object_label_value ? object_label_value.inspect : "N/A"
#              case object_label_value.type
#              when :IRI
#              when :Number
#              when :String
#                object_label = object_label_value.inspect
#              else
#                "N/A"
#              end
              if i < predicates.size - 1
                if j < objects.size - 1
                  puts "    |       |-- #{object} (#{object_label})"
                else
                  puts "    |       `-- #{object} (#{object_label})"
                end
              else
                if j < objects.size - 1
                  puts "            |-- #{object} (#{object_label})"
                else
                  puts "            `-- #{object} (#{object_label})"
                end
              end
            end
          end
        end
      end
    end

    class Schema < Chart
      require 'rexml/document'
      class REXML::Element
        def add_attribute_by_hash(attr_hash)
          attr_hash.each do |name, value|
            add_attribute(name.to_s, value)
          end
        end
      end

      FONT_FAMILY = 'Helvetica'.freeze
      RECT_WIDTH = 180.freeze
      RECT_HEIGHT = 50.freeze
      MARGIN_RECT = 30.freeze
      PREDICATE_AREA_WIDTH = 240.freeze
      PREDICATE_TRIANGLE_BASE_LEN = 10.freeze
      PREDICATE_TRIANGLE_HEIGHT = 13.freeze
      BNODE_RADIUS = 20.freeze

      START_X = 50.freeze
      START_Y = 10.freeze
      YPOS_CHANGE_NUM_OBJ = 8.freeze

      def initialize(model)
        super

        @svg_element = svg_element
        @current_x = START_X
        @current_y = START_Y
        @subject_ypos = START_Y
        @object_pos = {}
        @bnode = {}
        @num_objects = 0
      end

      def generate
        @model.subjects.each do |subject|
          @num_objects = 0
          generate_subject(subject)
          @current_x = START_X
          @subject_ypos = @current_y
        end

        output_svg
      end

      def generate_subject(subject)
        if @object_pos.key?(subject)
          @current_x = @object_pos[subject][:x]
          @current_y = @subject_ypos = @object_pos[subject][:y]
          draw_subject_rect = false
        else
          draw_subject_rect = true
        end

        if draw_subject_rect
          example = @model.subject_example_value(subject)
          uri_elements(@current_x, @subject_ypos, [subject, example], 'instance').each do |element|
            @svg_element.add_element(element)
          end
        end

        # Draw rdf:type
        move_to_predicate
        pos = predicate_arrow_position
        rdf_type = @model.subject_type_map[subject]
        predicate_arrow_elements(pos[:x1], pos[:y1], pos[:x2], pos[:y2], 'rdf_type', 'rdf:type').each do |element|
          @svg_element.add_element(element)
        end
        uri_elements(@current_x + PREDICATE_AREA_WIDTH, @current_y, rdf_type, 'class').each do |element|
          @svg_element.add_element(element)
        end
        @num_objects += 1

        move_to_next_object

        @model.predicates[subject].each do |predicate|
          paths = predicate.split(/\s*\/\s*/)
          if paths.size > 1
            bnode_predicate = paths.first
            if @bnode.keys.include?(bnode_predicate)
            else
              pos = predicate_arrow_position('bnode')
              predicate_arrow_elements(pos[:x1], pos[:y1], pos[:x2], pos[:y2], 'predicate', bnode_predicate).each do |element|
                @svg_element.add_element(element)
              end
              x = @current_x + PREDICATE_AREA_WIDTH
              y = @current_y
              @bnode[bnode_predicate] = {x: x, y: y}
              blank_node_elements(x, y).each do |element|
                @svg_element.add_element(element)
              end
              @num_objects += 1
              move_to_next_object
            end
          else
            generate_predicate(predicate)
            @model.objects[subject][predicate].each do |object|
              # Draw object rectangle
              generate_object(subject, object)
            end
          end
        end
      end

      def generate_predicate(predicate)
        pos = predicate_arrow_position
        predicate_arrow_elements(pos[:x1], pos[:y1], pos[:x2], pos[:y2], predicate_arrow_type(predicate), predicate).each do |element|
          @svg_element.add_element(element)
        end
      end

      def generate_object(subject, object)
        x = @current_x + PREDICATE_AREA_WIDTH
        example_value = @model.object_label_map[subject][object]
        inner_texts = [object, example_value.to_s]
        case example_value
        when String
          if literal_obj_type(example_value) == 'uri'
            uri_elements(x, @current_y, inner_texts).each do |element|
              @svg_element.add_element(element)
            end
          else
            object_literal_elements(x, @current_y, inner_texts, 'String').each do |element|
              @svg_element.add_element(element)
            end
          end
        when Integer
          object_literal_elements(x, @current_y, inner_texts, 'Int').each do |element|
            @svg_element.add_element(element)
          end
        end

        if /\A[A-Z]/ =~ object
          @object_pos[object] = { x: x, y: @current_y }
        end

        @num_objects += 1
        move_to_next_object
      end

      def output_svg
        svg_opts = {
            width: '2000px',
            height: '1500px',
            viewBox: "-0.5 -0.5 2000 1500"
        }
        @svg_element.add_attribute_by_hash(svg_opts)

        xml = xml_doc
        xml.add_element(@svg_element)
        xml.write($stdout, 2)
      end

      def uri_elements(x, y, inner_texts, type = 'instance')
        case type
        when 'instance'
          rect_fill = '#ffce9f'
        when 'class'
          rect_fill = '#fff4c3'
        end
        g_wrapper_element = REXML::Element.new('g')

        rect_element = REXML::Element.new('rect')
        rect_elem_opts = {
            x: x,
            y: y,
            width: RECT_WIDTH,
            height: RECT_HEIGHT,
            rx: '7.5',
            ry: '7.5',
            fill: rect_fill,
            stroke: '#000000',
            'stroke-width' => '3',
            'pointer-events' => 'all'
        }
        rect_element.add_attribute_by_hash(rect_elem_opts)
        g_wrapper_element.add_element(rect_element)
        g_wrapper_element.add_element(text_g_element(x, y, inner_texts))

        [g_wrapper_element]
      end

      def object_literal_elements(x, y, inner_texts, type = 'String')
        g_wrapper_element = REXML::Element.new('g')
        literal_rect_elements(x, y, type).each do |element|
          g_wrapper_element.add_element(element)
        end

        g_wrapper_element.add_element(text_g_element(x, y, inner_texts))

        [g_wrapper_element]
      end

      def literal_rect_elements(x, y, literal_type = 'String')
        g = REXML::Element.new('g')
        rect = REXML::Element.new('rect')
        rect_type = REXML::Element.new('rect')
        g_type = REXML::Element.new('g')
        text_type = REXML::Element.new('text')

        rect_opts = {
            x: x,
            y: y,
            width: '160',
            height: '50',
            fill: '#f8cecc',
            stroke: '#000000',
            'stroke-width' => '3',
            'pointer-events' => 'all'
        }
        rect.add_attribute_by_hash(rect_opts)
        g.add_element(rect)

        rect_type_opts = {
            x: x + 145,
            y: y + 15,
            width: '50',
            height: '20',
            fill: '#000000',
            stroke: '#000000',
            'stroke-width' => '3',
            transform: "rotate(-90,#{x + 170},#{y + 25})",
            'pointer-events' => 'all'
        }
        rect_type.add_attribute_by_hash(rect_type_opts)

        g_type_opts = {
            transform: "translate(-0.5 -0.5) rotate(-90 #{x + 170} #{y + 25})"
        }
        g_type.add_attribute_by_hash(g_type_opts)

        text_type_opts = {
            x: x + 170,
            y: y + 28,
            fill: '#ffffff',
            'font-family' => FONT_FAMILY,
            'font-size' => '12px',
            'font-style' => 'italic',
            'text-anchor' => 'middle',
            'font-weight' => 'bold'
        }
        text_type.add_attribute_by_hash(text_type_opts)
        text_type.add_text(literal_type)

        g_type.add_element(text_type)

        [g, rect_type, g_type]
      end

      def blank_node_elements(x, y)
        bnode_radius = 20

        g = REXML::Element.new('g')

        ellipse_opts = {
            cx: x + bnode_radius,
            cy: y + bnode_radius,
            rx: bnode_radius,
            ry: bnode_radius,
            fill: '#f2f2e9',
            stroke: '#000000',
            'stroke-dasharray' => '3 3',
            'pointer-events' => 'all'
        }
        ellipse = REXML::Element.new('ellipse')
        ellipse.add_attribute_by_hash(ellipse_opts)

        g.add_element(ellipse)

        [g]
      end

      def predicate_arrow_elements(x1, y1, x2, y2, type, legend = '')
        x_dist = (x2 - x1).abs.to_f
        y_dist = (y2 - y1).abs.to_f
        l_dist = distance(x1, y1, x2, y2)
        sin = y_dist / l_dist
        cos = x_dist / l_dist

        x3 = x2 - cos * PREDICATE_TRIANGLE_HEIGHT
        y3 = y2 - sin * PREDICATE_TRIANGLE_HEIGHT
        x4 = x3 - PREDICATE_TRIANGLE_BASE_LEN / 2 * sin
        y4 = y3 + PREDICATE_TRIANGLE_BASE_LEN / 2 * cos
        x5 = x3 + PREDICATE_TRIANGLE_BASE_LEN / 2 * sin
        y5 = y3 - PREDICATE_TRIANGLE_BASE_LEN / 2 * cos

        path_line_d = "M #{x1} #{y1} L #{x3} #{y3}"
        path_triangle_d = "M #{x2 - 2} #{y2} L #{x4} #{y4} L #{x5} #{y5} Z"

        g_top = REXML::Element.new('g')
        path_line = REXML::Element.new('path')
        path_triangle = REXML::Element.new('path')
        g_text = REXML::Element.new('g')
        switch_text = REXML::Element.new('switch')
        div_f = REXML::Element.new('div')
        div_s = REXML::Element.new('div')
        div_text = REXML::Element.new('div')
        foreign_object = REXML::Element.new('foreignObject')
        text = REXML::Element.new('text')

        case type
        when 'rdf_type'
          path_line_opts = {
              d: path_line_d,
              fill: 'none',
              stroke: '#000000',
              'stroke-width' => '3',
              'stroke-miterlimit' => '10',
              'stroke-dasharray' => '9 9',
              'pointer-events' => 'stroke'
          }
          path_triangle_opts = {
              d: path_triangle_d,
              fill: 'none',
              stroke: '#000000',
              'stroke-width' => '3',
              'stroke-miterlimit' => '10',
              'pointer-events' => 'all'
          }
        when 'predicate'
          path_line_opts = {
              d: path_line_d,
              fill: 'none',
              stroke: '#000000',
              'stroke-width' => '3',
              'stroke-miterlimit' => '10',
              'pointer-events' => 'stroke'
          }
          path_triangle_opts = {
              d: path_triangle_d,
              fill: '#000000',
              stroke: '#000000',
              'stroke-width' => '3',
              'stroke-miterlimit' => '10',
              'pointer-events' => 'all'
          }
        end

        path_line.add_attribute_by_hash(path_line_opts)
        path_triangle.add_attribute_by_hash(path_triangle_opts)

        g_text_opts = {
            transform: 'translate(-0.5 -0.5)'
        }
        g_text.add_attribute_by_hash(g_text_opts)

        text_x_pos = x1 + (x2 - x1) / 2
        text_y_pos = y1 + (y2 - y1) / 2
        foreign_object_opts = {
            style: 'overflow: visible; text-align: left;',
            'pointer-events' => 'none',
            width: '100%',
            height: '100%',
            requiredFeatures: 'http://www.w3.org/TR/SVG11/feature#Extensibility'
        }
        foreign_object.add_attribute_by_hash(foreign_object_opts)

        div_f_style = {
            display: 'flex',
            'align-items' => 'unsafe center',
            'justify-content' => 'unsafe center',
            width: '1px',
            height: '1px',
            'padding-top' => "#{text_y_pos}px",
            'margin-left' => "#{text_x_pos}px"
        }
        div_f_opts = {
            xmlns: 'http://www.w3.org/1999/xhtml',
            style: style_value_by_hash(div_f_style)
        }
        div_f.add_attribute_by_hash(div_f_opts)

        div_s_style = {
            'box-sizing' => 'border-box',
            'font-size' => 0,
            'text-align' => 'center'
        }
        div_s_opts = {
            style: style_value_by_hash(div_s_style)
        }
        div_s.add_attribute_by_hash(div_s_opts)

        div_text_style = {
            display: 'inline-block',
            'font-size' => '12px',
            'font-family' => FONT_FAMILY,
            color: '#000000',
            'line-height' => '1.2',
            'pointer-events' => 'all',
            'font-weight' => 'bold',
            'background-color' => '#ffffff',
            'white-space' => 'nowrap;'
        }
        div_text_opts = {
            style: style_value_by_hash(div_text_style)
        }
        div_text.add_attribute_by_hash(div_text_opts)
        div_text.add_text(legend)

        text_opts = {
            x: text_x_pos,
            y: text_y_pos,
            fill: '#000000',
            'font-family' => FONT_FAMILY,
            'font-size' => '12px',
            'text-anchor' => 'middle',
            'font-weight' => 'bold'
        }
        text.add_attribute_by_hash(text_opts)
        text.add_text(legend)

        div_s.add_element(div_text)
        div_f.add_element(div_s)
        foreign_object.add_element(div_f)
        switch_text.add_element(foreign_object)
        switch_text.add_element(text)

        g_top.add_element(path_line)
        g_top.add_element(path_triangle)
        g_top.add_element(switch_text)

        [g_top]
      end

      def foreign_object_element(x, y, inner_texts)
        element = REXML::Element.new('foreignObject')
        elem_opts = {
            style: 'overflow: visible; text-align: left;',
            'pointer-events' => 'none',
            width: '100%',
            height: '100%',
            requiredFeatures: 'http://www.w3.org/TR/SVG11/feature#Extensibility'
        }
        element.add_attribute_by_hash(elem_opts)

        div_f_element = REXML::Element.new('div')
        div_f_style_opts = {
            display: 'flex',
            'align-items' => 'unsafe center',
            'justify-content' => 'unsafe center',
            width: "#{RECT_WIDTH - 2}px",
            height: '1px',
            'padding-top' => "#{y + RECT_HEIGHT / 2}px",
            'margin-left' => "#{x + 1}px"
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
            'font-size' => '12px',
            'font-family' => FONT_FAMILY,
            color: '#000000',
            'line-height' => '1.2',
            'pointer-events' => 'all',
            'white-space' => 'normal',
            'word-wrap' => 'normal'
        }
        div_t_element.add_attribute('style', style_value_by_hash(div_t_style_opts))
        case inner_texts
        when String
          div_t_element.add_text(inner_texts)
        when Array
          inner_texts.each do |text|
            div = REXML::Element.new('div')
            div.add_text(text)
            div.add_element(REXML::Element.new('br'))
            div_t_element.add_element(div)
          end
        end

        div_s_element.add_element(div_t_element)
        div_f_element.add_element(div_s_element)
        element.add_element(div_f_element)

        element
      end

      def rect_text_element(x, y, inner_texts)
        element = REXML::Element.new('text')
        elem_opts = {
            x: x + RECT_WIDTH / 2,
            y: y + 29,
            fill: '#000000',
            'font-family' => FONT_FAMILY,
            'font-size' => '12px',
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

      def text_g_element(x, y, inner_texts)
        g = REXML::Element.new('g')
        g.add_attribute('transform', 'translate(-0.5 -0.5)')

        switch_element = REXML::Element.new('switch')
        switch_element.add_element(foreign_object_element(x, y, inner_texts))
        switch_element.add_element(rect_text_element(x, y, inner_texts))
        g.add_element(switch_element)

        g
      end

      def svg_element
        svg = REXML::Element.new('svg')
        svg.add_attribute('xmlns', 'http://www.w3.org/2000/svg')
        svg.add_attribute('style', 'background-color: rgb(255, 255, 255);')

        svg
      end

      def xml_doc
        doc = REXML::Document.new
        doc.add REXML::XMLDecl.new('1.0', 'UTF-8')
        doc.add REXML::DocType.new('svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"')

        doc
      end

      def rdf_type_predicate?(uri)
        ['a', 'rdf:type'].include?(uri)
      end

      def predicate_arrow_type(uri)
        if rdf_type_predicate?(uri)
          'rdf_type'
        else
          'predicate'
        end
      end

      def predicate_arrow_position(object_type = 'not_bnode')
        if object_type == 'bnode'
          {
              x1: @current_x,
              y1: @subject_ypos + RECT_HEIGHT / 2,
              x2: @current_x + PREDICATE_AREA_WIDTH,
              y2: @current_y + BNODE_RADIUS
          }
        else
          {
              x1: @current_x,
              y1: @subject_ypos + RECT_HEIGHT / 2,
              x2: @current_x + PREDICATE_AREA_WIDTH,
              y2: @current_y + RECT_HEIGHT / 2
          }
        end
      end

      def literal_obj_type(value)
        if /\A<.+\>\z/ =~ value
          'uri'
        else
          prefix, local_part = value.split(':')
          if @model.has_prefix?(prefix)
            'uri'
          else
            'literal'
          end
        end
      end

      def style_value_by_hash(hash)
        hash.map { |name, value| "#{name}: #{value}" }.join('; ')
      end

      def move_to_predicate
        @current_x += RECT_WIDTH
      end

      def move_to_next_object
        @current_y += RECT_HEIGHT + MARGIN_RECT
        if @num_objects == YPOS_CHANGE_NUM_OBJ
          @current_x -= RECT_WIDTH / 2
          @subject_ypos += RECT_HEIGHT / 2
        end
      end

      def distance(x1, y1, x2, y2)
        dx = (x2 - x1).abs.to_f
        dy = (y2 - y1).abs.to_f

        Math.sqrt(dx**2 + dy**2)
      end
    end
  end
end

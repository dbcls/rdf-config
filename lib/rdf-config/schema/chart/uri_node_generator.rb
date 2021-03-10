require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      class URINodeGenerator
        include Constant

        BEZIER_AREA = 8.freeze
        BEZIER_CONTROL = 3.6.freeze
        BEZIER_CONTROL_DIST = (BEZIER_AREA - BEZIER_CONTROL).round(1).freeze

        HLINE_WIDHT = (RECT_WIDTH - (BEZIER_AREA * 2)).freeze
        VLINE_HEIGHT = (RECT_HEIGHT - (BEZIER_AREA * 2)).freeze

        NAME_AREA_HEIGHT = 20.freeze
        NAME_AREA_VLINE_HEIGHT = (NAME_AREA_HEIGHT - BEZIER_AREA).freeze
        VALUE_AREA_HEIGHT = (RECT_HEIGHT - NAME_AREA_HEIGHT).freeze
        MARGIN_LEFT = 8.freeze
        MARGIN_RIGHT = 8.freeze

        def initialize(node, pos, opts = {})
          @node = node
          @pos = pos

          @disp_mode = opts.key?(:disp_mode) ? opts[:disp_mode] : :subject
        end

        def generate
          uri_elements
        end

        private

        def uri_elements
          wrapper = REXML::Element.new('g')
          wrapper.add_element(rect_element)
          wrapper.add_element(name_rect_element)
          wrapper.add_element(value_element)
          wrapper.add_element(name_element)
          wrapper.add_element(type_element)

          [wrapper]
        end

        def rect_element
          wrapper = REXML::Element.new('g')

          rect = REXML::Element.new('path')
          rect.add_attribute_by_hash(
            d: rect_paths.join(' '),
            class: 'st0'
          )

          wrapper.add_element(rect)
          wrapper.add_element(outline_element)

          wrapper
        end

        def outline_element
          outer_line = REXML::Element.new('path')
          outer_line.add_attribute_by_hash(
            d: rect_paths.join(' '),
            class: 'st1'
          )

          outer_line
        end

        def name_rect_element
          variable = REXML::Element.new('path')
          paths = ["M#{@pos.x},#{@pos.y + NAME_AREA_HEIGHT}"]
          paths << "v-#{NAME_AREA_VLINE_HEIGHT}"
          paths << "c0,-#{BEZIER_CONTROL_DIST} #{BEZIER_CONTROL},-#{BEZIER_AREA} #{BEZIER_AREA},-#{BEZIER_AREA}"
          paths << "h#{HLINE_WIDHT}"
          paths << "c#{BEZIER_CONTROL_DIST},0 #{BEZIER_AREA},#{BEZIER_CONTROL} #{BEZIER_AREA},#{BEZIER_AREA}"
          paths << "v#{NAME_AREA_VLINE_HEIGHT}"
          variable.add_attribute_by_hash(d: paths.join(' '))

          wrapper = REXML::Element.new('g')
          wrapper.add_attribute_by_hash(class: 'st2')
          wrapper.add_element(variable)

          wrapper
        end

        def value_element
          value = REXML::Element.new('text')
          value.add_attribute_by_hash(
            x: @pos.x + MARGIN_LEFT,
            y: @pos.y + NAME_AREA_HEIGHT + VALUE_MARGIN_TOP,
            class: 'st3 st4'
          )

          if @node.is_a?(Model::Subject) && @disp_mode == :object
            # value.add_text(@node.as_object_value)
            value.add_text(@node.value)
          else
            value.add_text(@node.value)
          end

          wrapper = REXML::Element.new('g')
          wrapper.add_attribute_by_hash(transform: 'translate(-0.5 -0.5)')
          wrapper.add_element(value)

          wrapper
        end

        def name_element
          name = REXML::Element.new('text')
          name.add_attribute_by_hash(
            x: @pos.x + MARGIN_LEFT,
            y: @pos.y + NAME_AREA_HEIGHT / 2,
            class: 'st5 st6 st7',
            'dominant-baseline' => 'middle'
          )

          if @node.is_a?(Model::Subject) && @disp_mode == :object
            # name.add_text(@node.as_object_name)
            name.add_text(@node.name)
          else
            name.add_text(@node.name)
          end

          wrapper = REXML::Element.new('g')
          wrapper.add_attribute_by_hash(transform: 'translate(-0.5 -0.5)')
          wrapper.add_element(name)

          wrapper
        end

        def type_element
          type = REXML::Element.new('text')
          type.add_attribute_by_hash(
            x: @pos.x + RECT_WIDTH - MARGIN_RIGHT,
            y: @pos.y + NAME_AREA_HEIGHT / 2,
            class: 'st8 st6 st7',
            'text-anchor' => 'end',
            'dominant-baseline' => 'middle'
          )
          type.add_text('URI')

          wrapper = REXML::Element.new('g')
          wrapper.add_attribute_by_hash(transform: 'translate(-0.5 -0.5)')
          wrapper.add_element(type)

          wrapper
        end

        def rect_paths
          paths = ["M#{@pos.x + RECT_WIDTH},#{@pos.y + RECT_HEIGHT - BEZIER_AREA}"]
          paths << "c0,#{BEZIER_CONTROL_DIST} -#{BEZIER_CONTROL},#{BEZIER_AREA} -#{BEZIER_AREA},#{BEZIER_AREA}"
          paths << "h-#{HLINE_WIDHT}"
          paths << "c-#{BEZIER_CONTROL_DIST},0 -#{BEZIER_AREA},-#{BEZIER_CONTROL} -#{BEZIER_AREA},-#{BEZIER_AREA}"
          paths << "v-#{VLINE_HEIGHT}"
          paths << "c0,-#{BEZIER_CONTROL_DIST} #{BEZIER_CONTROL},-#{BEZIER_AREA} #{BEZIER_AREA},-#{BEZIER_AREA}"
          paths << "h#{HLINE_WIDHT}"
          paths << "c#{BEZIER_CONTROL_DIST},0 #{BEZIER_AREA},#{BEZIER_CONTROL} #{BEZIER_AREA},#{BEZIER_AREA}"
          paths << "v#{VLINE_HEIGHT}"
          paths << 'z'

          paths
        end

      end
    end
  end
end

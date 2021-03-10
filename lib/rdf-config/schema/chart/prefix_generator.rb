require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      class PrefixGenerator
        TITLE_FONT_SIZE = 14
        PREFIX_FONT_SIZE = 12
        LINE_MARGIN = 4
        BOX_PADDING = 10

        class << self
          def area_height(num_prefixes)
            TITLE_FONT_SIZE + LINE_MARGIN + line_height * num_prefixes + BOX_PADDING * 2
          end

          def line_height
            PREFIX_FONT_SIZE + LINE_MARGIN
          end
        end

        def initialize(prefixes, pos, opts = {})
          case prefixes
          when Hash
            @prefixes = prefixes_by_hash(prefixes)
          when Array
            @prefixes = prefixes
          end

          @pos = pos
          @opts = opts

          @line_length = []
        end

        def generate
          wrapper = REXML::Element.new('g')

          x = @pos.x + BOX_PADDING
          y = @pos.y + BOX_PADDING
          wrapper.add_element(generate_title(x, y))
          y += TITLE_FONT_SIZE + LINE_MARGIN

          @prefixes.each do |prefix|
            wrapper.add_element(generate_prefix(prefix.keys.first, prefix.values.first, x, y))
            y += PrefixGenerator.line_height
          end

          wrapper.add_element(generate_box)

          [wrapper]
        end

        def width
          (@line_length.max * (PREFIX_FONT_SIZE * 0.5) + BOX_PADDING * 2).to_i
        end

        def height
          PrefixGenerator.area_height(@prefixes.size)
        end

        private

        def generate_title(x, y)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: x,
            y: y + TITLE_FONT_SIZE,
            'font-size' => "#{TITLE_FONT_SIZE}px",
            class: 'st6'
          )
          text.add_text('Namespaces')

          text
        end

        def generate_prefix(prefix, uri, x, y)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: x,
            y: y + PREFIX_FONT_SIZE,
            'font-size' => "#{PREFIX_FONT_SIZE}px",
            class: 'st3'
          )

          line = "#{prefix}: #{uri}"
          @line_length << line.length
          text.add_text(line)

          text
        end

        def generate_box
          rect = REXML::Element.new('rect')
          rect.add_attribute_by_hash(
            x: @pos.x,
            y: @pos.y,
            width: width,
            height: height,
            fill: 'none',
            stroke: '#000000',
            'stroke-width' => 1
          )

          rect
        end

        def prefixes_by_hash(hash)
          prefixes = []
          hash.each do |prefix, uri|
            prefixes << { prefix => uri }
          end

          prefixes
        end
      end
    end
  end
end

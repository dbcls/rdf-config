require 'rdf-config/schema/chart/constant'

class RDFConfig
  class Schema
    class Chart
      class TitleGenerator
        include Constant

        def initialize(title, pos, opts = {})
          @title = title
          @pos = pos
          @opts = opts
        end

        def generate
          wrapper = REXML::Element.new('g')
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: @pos.x,
            y: @pos.y + 10,
            'font-size' => TITLE_FONT_SIZE,
            'text-decoration' => 'underline'
          )
          text.add_text(@title)
          wrapper.add_element(text)

          [wrapper]
        end
      end
    end
  end
end

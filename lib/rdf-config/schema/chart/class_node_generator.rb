require 'rdf-config/schema/chart/node_element'

class RDFConfig
  class Schema
    class Chart
      class ClassNodeGenerator
        include NodeElement

        def initialize(node, pos)
          @node = node
          @pos = pos
        end

        def generate
          uri_elements(@pos, inner_texts, :class)
        end

        private

        def inner_texts
          case @node.value
          when Array
            @node.value
          else
            [@node.value]
          end
        end
      end
    end
  end
end

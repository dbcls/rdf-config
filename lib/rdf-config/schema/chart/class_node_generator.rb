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
          case @node.name
          when Array
            @node.name
          else
            [@node.name]
          end
        end
      end
    end
  end
end

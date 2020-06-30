require 'rdf-config/schema/chart/node_element'

class RDFConfig
  class Schema
    class Chart
      class URINodeGenerator
        include NodeElement

        def initialize(node, pos)
          @node = node
          @pos = pos
        end

        def generate
          uri_elements(@pos, inner_texts, :instance)
        end

        def inner_texts
          [@node.name, @node.value]
        end
      end
    end
  end
end

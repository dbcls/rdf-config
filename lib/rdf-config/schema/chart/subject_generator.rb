require 'rdf-config/schema/chart/node_element'
require 'rdf-config/schema/chart/blank_node_generator'

class RDFConfig
  class Schema
    class Chart
      class SubjectGenerator
        include NodeElement

        def initialize(subject, pos)
          @subject = subject
          @pos = pos
        end

        def generate
          if @subject.blank_node?
            generator = BlankNodeGenerator.new(@pos)
            generator.generate
          else
            inner_texts = [@subject.name, @subject.value]
            uri_elements(@pos, inner_texts, :instance)
          end
        end
      end
    end
  end
end

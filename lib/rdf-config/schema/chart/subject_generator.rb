require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'

class RDFConfig
  class Schema
    class Chart
      class SubjectGenerator
        def initialize(subject, pos)
          @subject = subject
          @pos = pos
        end

        def generate
          generator = if @subject.blank_node?
                        BlankNodeGenerator.new(@pos)
                      else
                        URINodeGenerator.new(@subject, @pos)
                      end

          generator.generate
        end
      end
    end
  end
end

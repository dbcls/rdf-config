require 'rdf-config/grasp/common_methods'
require 'rdf-config/grasp/base'

class RDFConfig
  class Grasp
    class ConstructGenerator < Base
      include CommonMethods

      def initialize(config, opts = {})
        super
      end

      def generate
        subject_type = @subject.name
        lines = ['CONSTRUCT {']
        lines << "#{INDENT}?#{subject_type} :#{IRI_ARG_NAME} ?#{subject_type} ."
        triples.each do |triple|
          lines << "#{INDENT}?#{subject_type} :#{triple.object_name} ?#{triple.object_name} ."
        end
        lines << '}'

        lines
      end
    end
  end
end

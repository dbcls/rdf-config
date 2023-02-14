require 'rdf-config/grasp/common_methods'
require 'rdf-config/grasp/base'
require 'rdf-config/sparql/where_generator'

class RDFConfig
  class Grasp
    class WhereGenerator < Base
      include CommonMethods

      def initialize(config, opts = nil)
        super
      end

      def generate
        opts = {
          query: object_names,
          indent_text: INDENT,
          check_query_name: false
        }

        where_generator = SPARQL::WhereGenerator.new(@config, opts)
        lines = where_generator.generate
        last_line = lines.pop
        lines << ''
        lines << iri_values_line
        lines << id_values_line
        lines << last_line

        lines
      end

      def iri_values_line
        %(#{INDENT}{{#if #{IRI_ARG_NAME}}}VALUES ?#{@subject.name} { {{join " " (as-iriref #{IRI_ARG_NAME})}} }{{/if}})
      end

      def id_values_line
        %(#{INDENT}{{#if #{ID_ARG_NAME}}}VALUES ?#{ID_ARG_NAME} { {{join " " (as-string #{ID_ARG_NAME})}} }{{/if}})
      end
    end
  end
end

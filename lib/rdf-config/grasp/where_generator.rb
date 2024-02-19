require 'rdf-config/grasp/common_methods'
require 'rdf-config/grasp/base'
require 'rdf-config/sparql/where_generator'

class RDFConfig
  class Grasp
    class WhereGenerator < Base
      include CommonMethods

      def initialize(config, opts = nil)
        super

        @endpoint = Endpoint.new(config)
        @graphs = @endpoint.graphs
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

        if has_graph?
          add_graph_phrase(lines)
        else
          lines
        end
      end

      def iri_values_line
        %(#{INDENT}{{#if #{IRI_ARG_NAME}}}VALUES ?#{@subject.name} { {{join " " (as-iriref #{IRI_ARG_NAME})}} }{{/if}})
      end

      def id_values_line
        %(#{INDENT}{{#if #{ID_ARG_NAME}}}VALUES ?#{ID_ARG_NAME} { {{join " " (as-string #{ID_ARG_NAME})}} }{{/if}})
      end

      def add_graph_phrase(where_lines)
        return lines unless has_graph?

        graph_added_lines = [where_lines.first]
        if @graphs.size == 1
          graph_added_lines << "#{INDENT}GRAPH <#{@graphs.first}> {"
        else
          graph_added_lines << "#{INDENT}VALUES ?g { #{@graphs.map { |graph| "<#{graph}>" }.join(' ')} }"
          graph_added_lines << "#{INDENT}GRAPH ?g {"
        end
        graph_added_lines += where_lines[1..-2].map { |line| "#{INDENT}#{line}" }
        graph_added_lines + ["#{INDENT}}", where_lines.last]
      end

      def has_graph?
        !@graphs.empty?
      end
    end
  end
end

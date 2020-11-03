require 'rdf-config/endpoint'

class RDFConfig
  class SPARQL
    class DatasetGenerator < SPARQL
      def initialize(config, opts = {})
        if opts.key?(:endpoint)
          endpoint = Endpoint.new(config, name: opts[:endpoint])
        elsif opts.key?('endpoint')
          endpoint = Endpoint.new(config, name: opts['endpoint'])
        else
          endpoint = Endpoint.new(config)
        end
        @graphs = endpoint.graphs
      rescue RDFConfig::Config::ConfigNotFound
        @graphs = []
      end

      def generate
        @graphs.map { |graph_iri| "FROM <#{graph_iri}>" }
      end
    end
  end
end

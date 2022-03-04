require 'rdf-config/endpoint'

class RDFConfig
  class SPARQL
    class DatasetGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        graphs.map { |graph_iri| "FROM <#{graph_iri}>" }
      end

      def graphs
        graphs = []
        @configs.each do |config|
          @config = config
          graphs += graphs_by_config
        end

        graphs.uniq
      end

      def graphs_by_config
        endpoint = if @opts.key?(:endpoint_name)
                     Endpoint.new(@config, name: @opts[:endpoint_name])
                   else
                     Endpoint.new(@config)
                   end
        endpoint.graphs
      rescue RDFConfig::Config::ConfigNotFound
        []
      end
    end
  end
end

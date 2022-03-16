class RDFConfig
  class Endpoint
    DEFAULT_NAME = 'endpoint'.freeze

    attr_reader :endpoints, :graphs

    def initialize(config, opts = {})
      @config = config
      @endpoint = config.endpoint

      endpoint_name = opts[:name] || DEFAULT_NAME
      @target = if endpoint_name.nil?
                  config_by_name(DEFAULT_NAME)
                else
                  config_by_name(endpoint_name)
                end
      if @target.nil?
        raise Config::InvalidConfig, %(ERROR: Endpoint "#{endpoint_name}" is not specified in endpoint.yaml file.)
      end

      @endpoints = []
      @graphs = []

      parse_config
    end

    def primary_endpoint
      @endpoints.first
    end

    def all_endpoints
      endpoints = []
      return endpoints unless @config.endpoint.is_a?(Hash)

      @config.endpoint.each_key do |endpoint_name|
        endpoint = Endpoint.new(@config, name: endpoint_name)
        endpoints += endpoint.endpoints
      end

      endpoints
    end

    private

    def parse_config
      case @target
      when String
        @endpoints = [@target]
      when Array
        parse_array_config(@target)
      end
    end

    def parse_array_config(array_config)
      array_config.each do |data|
        case data
        when String
          @endpoints << data if /\Ahttps?:\/\// =~ data
        when Hash
          if data.key?('graph')
            graphs = data['graph']
            case graphs
            when String
              @graphs << graphs
            when Array
              @graphs = graphs
            end
          end
        end
      end
    end

    def names
      @endpoint.keys
    end

    def config_by_name(name)
      @endpoint[name.to_s]
    end
  end
end

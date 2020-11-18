class RDFConfig
  class Endpoint
    DEFAULT_NAME = 'endpoint'

    attr_reader :endpoints, :graphs

    def initialize(config, opts = {})
      @endpoint = config.endpoint

      endpoint_name = opts[:name] || opts['name']
      unless endpoint_name.nil?
        @target = config_by_name(endpoint_name)
        raise Config::InvalidConfig, %Q(ERROR: Endpoint "#{endpoint_name}" is not specified in endpoint.yaml file.) if @target.nil?
      else
        @target = config_by_name(DEFAULT_NAME)
      end

      @endpoints = []
      @graphs = []

      parse_config
    end

    def primary_endpoint
      @endpoints.first
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

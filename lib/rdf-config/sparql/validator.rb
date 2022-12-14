class RDFConfig
  class SPARQL
    class Validator < SPARQL
      @instance = nil

      class << self
        def instance(config, opts)
          @instance ||= new(config, opts)
        end
      end

      def validate_done?
        @validate_done
      end

      def validate
        return if @validate_done

        if join?
          validate_join
        else
          validate_variables
        end
        validate_endpoint
        validate_options

        @validate_done = true

        raise InvalidSPARQLConfig, %(ERROR:\n#{@errors.map { |msg| "  #{msg}" }.join("\n")}) if error?
      end

      def validate_variables
        @configs.each do |config|
          @config = config
          validate_variables_by_config
        end
      end

      def validate_variables_by_config
        variables_handler.visible_variables.each do |variable_name|
          next if model.subject?(variable_name) || !model.find_object(variable_name).nil?

          add_warning("Variable name (#{variable_name}) not found in model.yaml file.")
        end
      end

      def validate_endpoint
        return unless @opts.key?(:endpoint_name)
        return if @config.endpoint.keys.include?(@opts[:endpoint_name])

        add_error(%(Endpoint "#{@opts[:endpoint_name]}" is not specified in endpoint.yaml file.))
      end

      def validate_options
        return if options.empty?

        validate_options_key
        validate_distinct
        validate_order_by
        validate_offset
        validate_limit
      end

      def validate_options_key
        invalid_keys = options.keys - OPTIONS_VALID_KEYS
        return if invalid_keys.empty?

        add_error(%(Invalid options #{invalid_keys.map { |key|
          "'#{key}'" }.join(', ')} in sparql.yaml file. Valid options are #{OPTIONS_VALID_KEYS.join(', ')}.))
      end

      def validate_order_by
        case options['order_by']
        when String
          validate_order_by_variable_name(options['order_by'])
        when Hash
          options['order_by'].each_key do |variable_name|
            validate_order_by_variable_name(variable_name)
          end
          options['order_by'].each do |variable_name, value|
            next if %w[ASC DESC].include?(value.upcase)

            add_error("The value of order_by '#{variable_name}' in sparql.yaml file must be either asc or desc.")
          end
        when Array
          options['order_by'].each do |item|
            case item
            when String
              validate_order_by_variable_name(item)
            when Hash
              validate_order_by_variable_name(item.keys.first)
            end
          end
        end
      end

      def validate_order_by_variable_name(variable_name)
        add_error(invalid_order_by_message(variable_name)) unless variables.include?(variable_name)
      end

      def invalid_order_by_message(variable_name)
        "Variable name '#{variable_name}' is set order_by option, but it is not contained in the variables."
      end

      def validate_distinct
        return if !options.key?('distinct') ||
                  [TrueClass, FalseClass].include?(options['distinct'].class)

        add_error("The value of option 'distinct' in sparql.yaml file must be either true or false.")
      end

      def validate_offset
        return if !options.key?('offset') || options['offset'].is_a?(Integer) || options['offset'].is_a?(TrueClass) || options['offset'].is_a?(FalseClass)

        add_error("The value of option 'offset' in sparql.yaml file must be an integer.")
      end

      def validate_limit
        return if !options.key?('limit') || options['limit'].is_a?(Integer) || options['limit'].is_a?(TrueClass) || options['limit'].is_a?(FalseClass)

        add_error("The value of option 'limit' in sparql.yaml file must be an integer.")
      end

      def validate_join; end

      def add_error(error_message)
        @errors << error_message
      end

      def error?
        !@errors.empty?
      end

      def add_warning(warn_message)
        @warnings << warn_message
      end

      def warning?
        !@warnings.empty?
      end

      def output_warning_messages
        return unless warning?

        warn @warnings.map { |msg| "WARNING: #{msg}" }.join("\n")
      end

      private

      def initialize(config, opts)
        super

        @validate_done = false
        @errors = []
        @warnings = []
      end
    end
  end
end

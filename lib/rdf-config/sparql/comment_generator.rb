class RDFConfig
  class SPARQL
    class CommentGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = generate_endpoint_lines
        return lines if join?

        lines << "# Description: #{description}"

        first_parameter = true
        parameters.each do |variable_name, value|
          if first_parameter
            first_parameter = false
            s = '# Parameter: '
          else
            s = '#            '
          end
          lines << "#{s}#{variable_name}: (example: #{value})"
        end
        lines << ''

        lines
      end

      private

      def generate_endpoint_lines
        return generate_no_endpoint_lines if endpoints.empty?

        endps = if join?
                  common_endpoints
                else
                  endpoints
                end
        lines = []
        lines << "# Endpoint: #{endpoints.first}"
        (1...endps.size).each do |i|
          lines << "#           #{endpoints[i]}"
        end

        lines
      end

      def generate_no_endpoint_lines
        ['# Endpoint: Please define a SPARQL endpoint in the endpoint.yaml file.']
      end

      def common_endpoints
        common_ep = nil
        @configs.each do |config|
          endpoint = Endpoint.new(config)
          if common_ep.nil?
            common_ep = endpoint.all_endpoints
          else
            common_ep &= endpoint.all_endpoints
          end
        end

        common_ep
      end
    end
  end
end

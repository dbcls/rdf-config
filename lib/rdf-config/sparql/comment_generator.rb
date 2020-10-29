class RDFConfig
  class SPARQL
    class CommentGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = generate_endpoint_lines

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

        lines = []
        lines << "# Endpoint: #{endpoints.first}"
        (1 ... endpoints.size).each do |i|
          lines << "#           #{endpoints[i]}"
        end

        lines
      end

      def generate_no_endpoint_lines
        ['# Endpoint: Please define a SPARQL endpoint in the endpoint.yaml file.']
      end
    end
  end
end

class RDFConfig
  class SPARQL
    class CommentGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = []

        lines << "# Endpoint: #{endpoints.first}"
        (1 ... endpoints.size).each do |i|
          lines << "#           #{endpoints[i]}"
        end

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
    end
  end
end


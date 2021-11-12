class RDFConfig
  class SPARQL
    class SolutionModifierGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = []

        lines << order_by_line if order_by
        lines << limit_line if limit
        lines << offset_line if offset

        lines
      end

      private

      def order_by_line
        return '' unless order_by

        case order_by
        when String
          # options:
          #   order_by: name
          "ORDER BY #{order_by_phase_by_variable_name(order_by)}"
        when Hash
          # options:
          #   order_by:
          #     nbrc_id: desc
          "ORDER BY #{order_by_phrase_by_hash(order_by)}"
        when Array
          # options:
          #   order_by:
          #     - habitat
          #     - location: desc
          order_by_line_by_array(order_by)
        else
          ''
        end
      end

      def order_by_phase_by_variable_name(variable_name)
        "?#{variable_name}"
      end

      def order_by_phrase_by_hash(hash)
        variable_name = hash.keys.first
        order_by = hash.values.first.upcase
        if order_by == 'DESC'
          "DESC(?#{variable_name})"
        else
          "?#{variable_name}"
        end
      end

      def order_by_line_by_array(order_by_array)
        (['ORDER BY'] + order_by_array.map do |item|
          case item
          when String
            order_by_phase_by_variable_name(item)
          when Hash
            order_by_phrase_by_hash(item)
          else
            ''
          end
        end).reject(&:empty?).join(' ')
      end

      def limit_line
        if limit
          "LIMIT #{limit}"
        else
          ''
        end
      end

      def offset_line
        if offset
          "OFFSET #{offset}"
        else
          ''
        end
      end
    end
  end
end

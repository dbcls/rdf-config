require_relative 'object'

class RDFConfig
  class Model
    class ValueList < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super

        @values = @value
        @value = @values.first
      end

      def instance_type
        'List'
      end

      def shex_data_type
        data_types = @values.map(&:shex_data_type).uniq
        if data_types.size == 1
          data_types.first
        else
          [
            '(', data_types.join(' OR '), ')'
          ].join
        end
      end

      def uri?
        first_instance.uri?
      end

      def literal?
        first_instance.literal?
      end

      def value_list?
        true
      end

      def subject?
        @values.select(&:subject?).size.positive?
      end

      def instances
        @values
      end

      def first_instance
        @values.first
      end

      def last_instance
        @values.last
      end
    end
  end
end

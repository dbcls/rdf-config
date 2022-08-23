class RDFConfig
  class Model
    class Object
      attr_reader :name, :value

      class << self
        def object_type(value, prefix_hash = {})
          case value
          when String
            if /\A<.+>\z/ =~ value
              :uri
            else
              prefix, local_part = value.split(':', 2)
              if prefix_hash.keys.include?(prefix)
                :uri
              else
                :literal
              end
            end
          else
            :literal
          end
        end

        def blank_node?(object_name)
          case object_name
          when Array
            true
          when String
            @name == '[]'
          else
            false
          end
        end
      end

      def initialize(object, prefix_hash = {})
        case object
        when Hash
          @name = object.keys.first
          @value = object[@name]
        else
          @name = ''
          @value = object
        end
      end

      def type
        ''
      end

      def data_type_by_string_value(value)
        if /\^\^(?<prefix>\w+):(?<local_part>.+)\z/ =~ value
          if prefix == 'xsd'
            case local_part
            when 'integer'
              'Int'
            when /\A[a-z0-9]+\z/
              local_part.capitalize
            else
              local_part.dup
            end
          else
            "#{$1}:#{$2}"
          end
        else
          'String'
        end
      end

      def uri?
        false
      end

      def literal?
        false
      end

      def blank_node?
        false
      end
    end
  end
end

require_relative 'uri'
require_relative 'literal'
require_relative 'blank_node'
require_relative 'value_list'
require_relative 'unknown'

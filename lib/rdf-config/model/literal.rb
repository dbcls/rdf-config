require_relative 'object'

class RDFConfig
  class Model
    class Literal < RDFConfig::Model::Object
      def initialize(object_hash, prefix_hash = {})
        super
      end

      def type
        case @value
        when Integer
          'Int'
        when TrueClass
          'Boolean'
        when FalseClass
          'Boolean'
        when String
          data_type_by_string_value(@value)
        else
          @value.class.to_s
        end
      end

      def literal?
        true
      end

      def has_lang_tag?
        /\A".*"@[\w\-]+\z/ =~ @value.to_s.strip
      end

      def has_data_type?
        /\A".*"\^\^.+\z/ =~ @value.to_s.strip
      end

      def rdf_data_type
        case @value
        when String
          if /\^\^(?<prefix>\w+)\:(?<local_part>.+)\z/ =~ value
            "#{prefix}:#{local_part}"
          else
            'xsd:string'
          end
        else
          "xsd:#{@value.class.to_s.downcase}"
        end
      end
    end
  end
end

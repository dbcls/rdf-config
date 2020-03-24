class RDFConfig
  class Model
    Property = Struct.new(:predicate, :object)

    class Subject
      attr_reader :name, :value, :properties, :property_hash

      def initialize(subject_hash, prefix_hash = {})
        @prefix_hash = prefix_hash

        key = subject_hash.keys.first
        @property_hash = subject_hash[key]
        @name, @value = key.split(/\s+/, 2)
        @properties = []
        subject_hash[key].each do |property_hash|
          add_property(property_hash)
        end
      end

      def add_property(property_hash)
        predicate = property_hash.keys.first
        object = property_hash[predicate]

        case object
        when Array
          object.each do |obj|
            obj_inst = Object.instance(obj, @prefix_hash)
            if obj_inst.blank_node?
              obj_inst.value.each do |bnode_property|
                add_property(bnode_property)
              end
            else
              @properties << property_instance(predicate, obj_inst)
            end
          end
        when Hash
          @properties << property_instance(predicate, objects)
        end
      end

      def property_instance(predicate, object)
        case object
        when Hash
          object = Oject.instance(object, @prefix_hash)
        end

        Property.new(Predicate.new(predicate), object)
      end
    end

    class Predicate
      attr_reader :uri

      def initialize(predicate)
        @uri = predicate
      end

      def rdf_type?
        %w[a rdf:type].include?(@uri)
      end
    end

    class Object
      class << self
        def instance(object, prefix_hash = {})
          case object
          when Hash
            name = object.keys.first
            value = object[name]
          when String
            # object is object value, name is not available
            name = nil
            value = object
          end

          if blank_node?(name)
            BlankNode.new(object)
          else
            if value.nil?
              Unknown.new(object, prefix_hash)
            else
              case format(value, prefix_hash)
              when :uri
                URI.new(object)
              when :literal
                Literal.new(object)
              end
            end
          end
        end

        def format(value, prefix_hash = {})
          case value
          when String
            if /\A<.+\>\z/ =~ value
              :uri
            else
              prefix, local_part = value.split(':')
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

      attr_reader :name, :value, :optional

      def initialize(object, prefix_hash = {})
        case object
        when Hash
          @name = object.keys.first
          @value = object[@name]
        else
          @name = object
          @value = nil
        end

        @attribute = nil
        @optional = false
        last_char = @name[-1]
        if %w[+ * ?].include?(last_char)
          @name = @name[0..-2]
          @attribute = last_char
          if %w[* ?].include?(last_char)
            @optional = true
          end
        end
      end

      def data_type
        case @value
        when Integer
          'Int'
        when String
          data_type_by_string_value(@value)
        else
          @value.class.to_s
        end
      end

      def data_type_by_string_value(value)
        if /\^\^(\w+)\:(.+)\z/ =~ value
          if $1 == 'xsd'
            case $2
            when 'string'
              'String'
            when 'integer'
              'Int'
            else
              $2.capitalize
            end
          else
            "#{$1}:#{$2}"
          end
        else
          'String'
        end
      end

      def format
        :unknown
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

    class URI < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def format
        :uri
      end

      def uri?
        true
      end
    end

    class Literal < RDFConfig::Model::Object
      def initialize(object_hash, prefix_hash = {})
        super
      end

      def format
        :literal
      end

      def literal?
        true
      end
    end

    class BlankNode < RDFConfig::Model::Object
      def initalize(object, prefixe_hash = {})
        super
      end

      def format
        :bnode
      end

      def blank_node?
        true
      end
    end

    class Unknown < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end
    end
  end
end

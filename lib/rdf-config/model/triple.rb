class RDFConfig
  class Model
    Property = Struct.new(:predicate, :object, :property_paths)
    Cardinality = Struct.new(:min, :max)

    class Subject
      attr_reader :name, :value, :properties, :property_hash

      def initialize(subject_hash, prefix_hash = {})
        @prefix_hash = prefix_hash

        key = subject_hash.keys.first
        @property_hash = subject_hash[key]
        @name, @value = key.split(/\s+/, 2)
        @properties = []

        @property_paths = []
        subject_hash[key].each do |property_hash|
          add_property(property_hash)
        end
      end

      def rdf_type
        type = nil
        properties.each do |property|
          if property.predicate.rdf_type?
            type = property.object.name
            break
          end
        end

        if type.nil?
          raise SubjectClassNotFound, "Subject: #{subject_name}: rdf_type not found."
        end

        type
      end

      def add_property(property_hash)
        predicate_key = property_hash.keys.first
        predicate = Predicate.new(predicate_key)
        object = property_hash[predicate_key]

        case object
        when Array
          object.each do |obj|
            obj_inst = Object.instance(obj, @prefix_hash)
            if obj_inst.blank_node?
              @property_paths << predicate.uri
              obj_inst.value.each do |bnode_property|
                add_property(bnode_property)
              end
              @property_paths.pop
            else
              @properties << property_instance(predicate, obj_inst)
            end
          end
        when Hash
          @properties << property_instance(predicate, object)
        when String
          @properties << property_instance(predicate, object)
        end
      end

      def property_instance(predicate, object)
        case object
        when Hash
          object = Object.instance(object, @prefix_hash)
        when String
          object = Object.instance(object, @prefix_hash)
        end

        Property.new(predicate, object, @property_paths.dup.push(predicate.uri))
      end
    end

    class Predicate
      attr_reader :uri, :cardinality

      def initialize(predicate)
        @uri = predicate
        @cardinality = nil

        interpret_cardinality
      end

      def interpret_cardinality
        last_char = @uri[-1]
        case last_char
        when '?', '*', '+'
          handle_char_cardinality(last_char)
        when '}'
          handle_range_cardinality
        end
      end

      def rdf_type?
        %w[a rdf:type].include?(@uri)
      end

      def sparql_optional_phrase?
        @cardinality.is_a?(Cardinality) && (@cardinality.min.nil? || @cardinality.min == 0)
      end

      def handle_char_cardinality(cardinality)
        @uri = @uri[0..-2]

        case cardinality
        when '?'
          @cardinality = Cardinality.new(0, 1)
        when '*'
          @cardinality = Cardinality.new(0, nil)
        when '+'
          @cardinality = Cardinality.new(1, nil)
        end
      end

      def handle_range_cardinality
        pos = @uri.rindex('{')
        range = @uri[pos + 1..-2]
        @uri = @uri[0..pos - 1]
        if range.index(',')
          min, max = range.split(/\s*,\s*/)
          @cardinality = Cardinality.new(min.to_s == '' ? nil : min.to_i, max.to_s == '' ? nil : max.to_i)
        else
          @cardinality = Cardinality.new(range.to_i, range.to_i)
        end
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

      attr_reader :name, :value

      def initialize(object, prefix_hash = {})
        case object
        when Hash
          @name = object.keys.first
          @value = object[@name]
        else
          @name = object
          @value = nil
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

class RDFConfig
  class Model
    Cardinality = Struct.new(:label, :min, :max)

    class Triple
      attr_reader :subject, :predicates, :object

      def initialize(subject, predicates, object)
        @subject = subject
        @predicates = predicates
        @object = object
      end

      def predicate
        @predicates.last
      end

      def property_path(separator = ' / ')
        @predicates.map(&:uri).join(separator)
      end

      def last_predicate?(model)
        last_property_path = model.select { |triple| triple.subject.name == subject.name }.last.property_path

        property_path == last_property_path
      end

      def last_object?(model)
        idx = model.find_index(self)

        model.size == idx + 1 || model[idx].property_path != model[idx + 1].property_path
      end

      def subject_name
        @subject.name
      end

      def object_name
        case @object
        when Model::Subject
          @object.as_object_name(subject.name)
        else
          @object.name
        end
      end

      def object_value
        case @object
        when Model::Subject
          @object.as_object_value(subject.name)
        else
          @object.value
        end
      end

      def bnode_connecting?
        @predicates.size > 1
      end
    end

    class Graph
      attr_reader :subjects, :object_value

      def initialize(config, opts = {})
        @config = config
        @opts = opts
        @subject_names = config.model.map { |hash| hash.keys }.flatten

        @subjects = []
        @object_value = {}

        @target_subject = nil
      end

      def generate
        @subjects = @config.model.map { |subject_hash| Subject.new(subject_hash, prefix_hash) }
        @subjects.each_with_index do |subject, i|
          @target_subject = subject
          setup_subject(subject, @config.model[i])
        end

        @subjects
      end

      private

      def setup_subject(subject, subject_hash)
        subject_hash.each do |subject_name, predicate_object_hashes|
          predicate_object_hashes.each do |predicate_object_hash|
            subject.add_predicate(predicate_instance(predicate_object_hash))
          end
        end
      end

      def predicate_instance(predicate_object_hash)
        predicate_uri = predicate_object_hash.keys.first
        predicate = Predicate.new(predicate_uri, prefix_hash)
        object_data = predicate_object_hash[predicate_uri]
        case object_data
        when String, Hash
          predicate.add_object(object_instance(object_data))
        when Array
          object_data.each do |obj_data|
            predicate.add_object(object_instance(obj_data))
          end
        end

        predicate
      end

      def object_instance(object_data)
        case object_data
        when Hash
          name = object_data.keys.first
          value = object_data[name]
          @object_value[name] = value
        when String
          # object is object value, name is not available
          name = nil
          value = object_data
        end

        subject = @subjects.select { |subject| subject.name == value }.first
        unless subject.nil?
          subject.add_as_object(@target_subject.name, Literal.new(name => value))
          return subject
        end

        if Object.blank_node?(name)
          bnode = BlankNode.new(object_data, prefix_hash)
          setup_subject(bnode.value, object_data)
          bnode
        else
          if value.nil?
            Unknown.new(object_data, prefix_hash)
          elsif value.is_a?(Array)
            ValueList.new({ name => value.map { |v| object_instance(name => v) } }, prefix_hash)
          else
            case Object.object_type(value, prefix_hash)
            when :uri
              URI.new(object_data, prefix_hash)
            when :literal
              Literal.new(object_data, prefix_hash)
            end
          end
        end
      end

      def prefix_hash
        @config.prefix
      end
    end

    class Subject
      attr_reader :name, :value, :predicates, :as_object

      def initialize(subject_hash, prefix_hash = {})
        @prefix_hash = prefix_hash
        @as_object = {}

        key = subject_hash.keys.first
        if key.is_a?(Array)
          @name = key
          @value = nil
        else
          @name, @value = key.split(/\s+/, 2)
        end

        @predicates = []
      end

      def types
        rdf_type_predicates = @predicates.select(&:rdf_type?)
        rdf_type_predicates.map { |predicate| predicate.objects.map(&:name) }.flatten
      end

      def type(separator = ', ')
        types.join(separator)
      end

      def blank_node?
        @name.is_a?(Array)
      end

      def objects
        @predicates.map(&:objects).flatten
      end

      def add_predicates(predicate_object_hashes)
        predicate_object_hashes.each do |predicate_object_hash|
          add_predicate(predicate_object_hash)
        end
      end

      def add_predicate(predicate)
        @predicates << predicate
      end

      def add_as_object(subject_name, object)
        @as_object[subject_name] = object
      end

      def as_object_name(subject_name)
        @as_object.key?(subject_name) ? @as_object[subject_name].name : nil
      end

      def as_object_value(subject_name)
        @as_object.key?(subject_name) ? @as_object[subject_name].value : nil
      end

      def used_as_object?
        !@as_object.empty?
      end
    end

    class Predicate
      attr_reader :name, :uri, :objects, :cardinality

      def initialize(predicate, prefix_hash = {})
        @name = predicate
        @uri = predicate == 'a' ? 'rdf:type' : predicate
        @prefix_hash = prefix_hash
        @cardinality = nil

        @objects = []

        interpret_cardinality
      end

      def add_object(object)
        @objects << object
      end

      def rdf_type?
        %w[a rdf:type].include?(@uri)
      end

      def required?
        @cardinality.nil? || !@cardinality.min.nil? && @cardinality.min > 0
      end

      def plural?
        !@cardinality.nil? && (@cardinality.max.nil? || @cardinality.max > 1)
      end

      private

      def interpret_cardinality
        last_char = @uri[-1]
        case last_char
        when '?', '*', '+'
          proc_char_cardinality(last_char)
        when '}'
          proc_range_cardinality
        end
      end

      def proc_char_cardinality(cardinality)
        @uri = @uri[0..-2]

        case cardinality
        when '?'
          @cardinality = Cardinality.new(cardinality, 0, 1)
        when '*'
          @cardinality = Cardinality.new(cardinality, 0, nil)
        when '+'
          @cardinality = Cardinality.new(cardinality, 1, nil)
        end
      end

      def proc_range_cardinality
        pos = @uri.rindex('{')
        range = @uri[pos + 1..-2]
        @uri = @uri[0..pos - 1]
        if range.index(',')
          min, max = range.split(/\s*,\s*/)
          @cardinality = Cardinality.new("{#{range}}", min.to_s == '' ? nil : min.to_i, max.to_s == '' ? nil : max.to_i)
        else
          @cardinality = Cardinality.new("{#{range}}", range.to_i, range.to_i)
        end
      end
    end

    class Object
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

      def type
        ''
      end

      def data_type_by_string_value(value)
        if /\^\^(?<prefix>\w+)\:(?<local_part>.+)\z/ =~ value
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

      class << self
        def object_type(value, prefix_hash = {})
          case value
          when String
            if /\A<.+\>\z/ =~ value
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
    end

    class URI < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def type
        'URI'
      end

      def uri?
        true
      end
    end

    class Literal < RDFConfig::Model::Object
      def initialize(object_hash, prefix_hash = {})
        super
      end

      def type
        case @value
        when Integer
          'Int'
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

    class ValueList < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end
    end

    class BlankNode < RDFConfig::Model::Object
      def initialize(object, prefixe_hash = {})
        super
        @value = Subject.new({ @name => @value }, prefixe_hash)
      end

      def type
        'BNODE'
      end

      def blank_node?
        true
      end

      def rdf_type_uri
        @name
      end
    end

    class Unknown < RDFConfig::Model::Object
      def initialize(object, prefix_hash = {})
        super
      end

      def type
        'N/A'
      end
    end
  end
end

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

      def object_name(predicate_uri = nil)
        case @object
        when Model::Subject
          @object.as_object_name
        else
          @object.name
        end
      end

      def object_value(predicate_uri = nil)
        case @object
        when Model::Subject
          @object.as_object_value
        else
          @object.value
        end
      end

      def bnode_connecting?
        @predicates.size > 1
      end

      def ==(other)
        self.subject.name == other.subject.name &&
          self.property_path == other.property_path &&
          self.object_name == other.object_name
      end

      def to_s
        "#{subject.name} #{property_path} #{object_name}"
      end
    end

    class Graph
      attr_reader :subjects, :object_names, :object_value, :errors, :warnings

      def initialize(config, opts = {})
        @config = config
        @opts = opts
        @subject_names = config.model.map { |hash| hash.keys }.flatten

        @subjects = []
        @object_names = []
        @object_value = {}

        @target_subject = nil
        @current_predicate_uri = nil

        @errors = []
        @warnings = []
      end

      def generate
        @subjects = @config.model.map { |subject_hash| Subject.new(subject_hash, prefix_hash) }
        @subjects.each_with_index do |subject, i|
          @target_subject = subject
          setup_subject(subject, @config.model[i])
        end

        @subjects
      end

      def error?
        !@errors.empty?
      end

      private

      def setup_subject(subject, subject_hash)
        validate_subject(subject)
        subject_hash.each do |subject_name, predicate_object_hashes|
          predicate_object_hashes.each do |predicate_object_hash|
            unless predicate_object_hash.is_a?(Hash)
              add_error("It seems that the predicate and object settings in subject (#{subject_name}) are incorrect in the model.yaml file.")
              next
            end

            predicate_object_hash.each do |predicate, object|
              setup_predicate(subject, predicate, object)
            end
          end
        end
      end

      def setup_predicate(subject, predicate, object)
        if object.nil?
          add_error("Predicate (#{predicate}) has no RDF object setting.")
        else
          pred_inst = predicate_instance({ predicate => object })
          unless pred_inst.nil?
            @target_predicate = pred_inst
            validate_predicate(pred_inst)
            subject.add_predicate(pred_inst)
          end
        end
      end

      def predicate_instance(predicate_object_hash)
        predicate_uri = predicate_object_hash.keys.first
        predicate_uri = predicate_uri.strip if predicate_uri.is_a?(String)
        object_data = predicate_object_hash[predicate_uri]
        if object_data.nil?
          return nil
        end

        predicate = Predicate.new(predicate_uri, prefix_hash)
        @current_predicate_uri = predicate.uri
        case object_data
        when String
          predicate.add_object(object_instance(object_data))
        when Hash
          add_error("RDF object data (predicate is '#{predicate.uri}') in model.yaml is not an array. Please specify the RDF object data as an array.")
        when Array
          object_data.each do |obj_data|
            if obj_data.is_a?(Hash)
              object_name = obj_data.keys.first
              add_object_name(object_name) if object_name.is_a?(String)
            end
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
          subject_as_object = subject.clone
          # name is object_name in model.yaml, value is object_value == subject_name in model.yaml
          subject_as_object.add_as_object(@target_subject.name, @current_predicate_uri, Literal.new(name => value))
          return subject_as_object
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

      def validate_subject(subject)
        return if subject.blank_node?

        # Subject name must be CamelCase
        if /\A[A-Z][A-Za-z0-9]*\z/ !~ subject.name
          add_error(%/Invalid subject name (#{subject.name}) in model.yaml file. Subject name must start with a capital letter and only alphanumeric characters can be used in subject name./)
        end

        subject_value = subject.value.to_s.strip
        return if subject_value.empty?

        # Subject value must be valid URI
        validate_result, prefix = validate_uri(subject_value)
        case validate_result
        when 'NOT_URI'
          add_error("Subject (#{subject.name}), value (#{subject_value}) is not valid URI.")
        when 'NO_PREFIX'
          add_error("Prefix (#{prefix}) used in subject (#{subject.name}), value (#{subject_value}) but not defined in prefix.yaml file.")
        end
      end

      def validate_predicate(predicate)
        if predicate.rdf_type?
          validate_rdf_type_predicate(predicate)
        else
          validate_non_rdf_type_predicate(predicate)
        end
      end

      def validate_rdf_type_predicate(predicate)
        predicate.objects.each do |object|
          # object.name is URI of rdf:type
          uri = object.name
          validate_result, prefix = validate_uri(uri)
          case validate_result
          when 'NOT_URI'
            add_error("rdf:type (#{uri}) is not valid URI.")
          when 'NO_PREFIX'
            add_error("Prefix (#{prefix}) used in rdf:type (#{uri}) but not defined in prefix.yaml file.")
          end
        end
      end

      def validate_non_rdf_type_predicate(predicate)
        predicate.objects.each do |object|
          uri = predicate.uri
          validate_result, prefix = validate_uri(uri)
          case validate_result
          when 'NOT_URI'
            add_error("Predicate (#{uri}) is not valid URI.")
          when 'NO_PREFIX'
            add_error("Prefix (#{prefix}) used in predicate (#{uri}) but not defined in prefix.yaml file.")
          end

          return if object.is_a?(Subject) || object.is_a?(BlankNode)

          object_name = object.name
          if object_name.is_a?(String)
            validate_object_name(object_name)
          end
        end
      end

      def validate_object(object)
        if object.is_a?(Model::URI)
          uri = object.value.to_s.strip
          unless uri.empty?
            validate_result, prefix = validate_uri(uri)
            case validate_result
            when 'NOT_URI'
              add_error("Object (#{object.name}, value (#{uri}) is not valid URI.")
            when 'NO_PREFIX'
              add_error("Prefix (#{prefix}) used in object (#{object.name}, value (#{uri}) but not defined in prefix.yaml file.")
            end
          end
        end
      end

      def validate_object_name(object_name)
        # object name must be snake_case
        if /\A[a-z0-9_]+\z/ !~ object_name
          add_error("Invalid object name (#{object_name}) in model.yaml file. Only lowercase letters, numbers and underscores can be used in object name.")
        end
      end

      def validate_uri(uri)
        if /\A<.+>\z/ =~ uri
          ['VALID']
        else
          prefix, local_part = uri.split(':', 2)
          if local_part.nil?
            ['NOT_URI']
          elsif !prefix_hash.keys.include?(prefix)
            ['NO_PREFIX', prefix]
          end
        end
      end

      def prefix_hash
        @config.prefix
      end

      def add_object_name(object_name)
        return if object_name.to_s.empty?

        @object_names << object_name
      end

      def add_error(message)
        @errors << message unless @errors.include?(message)
      end

      def add_warning(message)
        @warnings << message unless @warnings.include?(message)
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

      def object_names
        @predicates.reject(&:rdf_type?).map(&:objects).flatten.map do |object|
          if object.is_a?(Subject)
            object.as_object_name
          else
            object.name
          end
        end
      end

      def add_predicates(predicate_object_hashes)
        predicate_object_hashes.each do |predicate_object_hash|
          add_predicate(predicate_object_hash)
        end
      end

      def add_predicate(predicate)
        @predicates << predicate
      end

      def add_as_object(subject_name, predicate_uri, object)
        @as_object = {
          subject_name: subject_name,
          predicate_uri: predicate_uri,
          object: object
        }
      end

      def parent_subject_names
        if used_as_object?
          @as_object.keys
        else
          []
        end
      end

      def as_object_name
        @as_object[:object].name
      end

      def as_object_value
        @as_object[:object].value
      end

      def used_as_object?
        !@as_object.empty?
      end

      def ==(other)
        self.name == other.name
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

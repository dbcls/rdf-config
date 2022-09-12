class RDFConfig
  class Model
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

            if !predicate.rdf_type? && !obj_data.is_a?(Hash)
              add_warning(%|The object variable name for #{@target_subject.name}/#{predicate_uri} needs to be set.|)
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
          # object.value is URI of rdf:type
          uri = object.value
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

          #--> return if object.is_a?(Subject) || object.is_a?(BlankNode)
          next if predicate.rdf_type? || object.value.to_s.empty?

          object_name = if object.is_a?(Subject)
                          begin
                            object.as_object[:object].name
                          rescue StandardError
                            ''
                          end
                        else
                          object.name
                        end
          validate_object_name(object_name) if object_name.is_a?(String) && !object_name.empty?
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
  end
end

class RDFConfig
  class Model
    class Validator
      attr_reader :errors

      def initialize(model, config)
        @model = model
        @config = config

        @errors = []
        @undefined_prefixes = []
        @num_subject_name = {}
        @num_variable = {}
      end

      def validate
        @model.subjects.each do |subject|
          add_subject_name(subject.name)
          validate_subject(subject)
        end

        validate_subject_name
        validate_variable
        validate_objects
      end

      def error?
        !@errors.empty?
      end

      def error_message
        %Q/ERROR: Invalid configuration\n#{errors.map { |msg| "  #{msg}" }.join("\n")}/
      end

      private

      def validate_subject(subject)
        unless subject.blank_node?
          if /\A\w+\z/ !~ subject.name
            add_error(%/Invalid subject name (#{subject.name}) in model.yaml file. Only alphanumeric characters and underscores can be used in subject name./)
          end
        end

        validate_resource_class(subject)
        validate_prefix(subject.value)
        subject.predicates.each do |predicate|
          validate_predicate(predicate)
        end
      end

      def validate_subject_name
        @num_subject_name.select { |subject_name, num_subject_name| num_subject_name > 1 }.keys.each do |subject_name|
          add_error(%/Duplicate subject name (#{subject_name}) in model.yaml file./)
        end

        @num_subject_name.keys.each do |subject_name|
          if @num_variable.key?(subject_name) && @num_variable[subject_name] == 1
            add_error(%/Duplicate variable name (#{subject_name}) in model.yaml file./)
          end
        end
      end

      def validate_predicate(predicate)
        validate_prefix(predicate.name)
        predicate.objects.each do |object|
          if predicate.rdf_type?
            case object.name
            when Array
              object.name.each do |rdf_type|
                validate_prefix(rdf_type.to_s)
              end
            else
              validate_prefix(object.name.to_s)
            end
          end
        end
      end

      def validate_objects
        @model.each do |triple|
          next if triple.predicate.rdf_type?

          object = triple.object
          if !object.is_a?(BlankNode) && !object.is_a?(Subject) && object.name.to_s.size > 0
            if /\A\w+\z/ !~ object.name
              add_error(%/Invalid object name (#{object.name}) in model.yaml file. Only alphanumeric characters and underscores can be used in object name./)
            end
            add_variable_name(object.name)
          end

          validate_prefix(object.value) if object.is_a?(URI)
        end
      end

      def validate_resource_class(subject)
        return if subject.blank_node?

        add_error(%/Subject (#{subject.name}) has no rdf:type./) if subject.types.empty?
      end

      def validate_prefix(uri)
        return if /\A<.+>\z/ =~ uri.to_s

        if /\A(?<prefix>\w+)\:/ =~ uri.to_s
          return if @config.prefix.key?(prefix) || @undefined_prefixes.include?(prefix)

          add_undefined_prefixes(prefix)
          add_error(%/Prefix (#{prefix}) used but not defined in prefix.yaml file./)
        end
      end

      def validate_variable
        @num_variable.select { |k, v| v > 1 }.each do |variable_name, num_variable|
          add_error(%/Duplicate variable name (#{variable_name}) in model.yaml file./)
        end
      end

      def add_error(error_message)
        @errors << error_message
      end

      def add_subject_name(subject_name)
        if @num_subject_name.key?(subject_name)
          @num_subject_name[subject_name] += 1
        else
          @num_subject_name[subject_name] = 1
        end
      end

      def add_undefined_prefixes(prefix)
        @undefined_prefixes << prefix unless @undefined_prefixes.include?(prefix)
      end

      def add_variable_name(variable_name)
        if @num_variable.key?(variable_name)
          @num_variable[variable_name] += 1
        else
          @num_variable[variable_name] = 1
        end
      end
    end
  end
end

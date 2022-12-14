class RDFConfig
  class Model
    class Validator
      attr_reader :errors, :warnings

      def initialize(model, config)
        @model = model
        @config = config

        @errors = []
        @warnings = []
        @num_subject_name = {}
        @num_variable = {}
      end

      def validate
        unless @model.subjects.select(&:blank_node?).empty?
          add_error('Blank node subject exists in the model.yaml file. Blank node subjects are not allowed.')
        end

        @model.subjects.each do |subject|
          add_subject_name(subject.name)
          validate_subject(subject)
        end

        validate_subject_name
        validate_by_object_names
        validate_variable
      end

      def error?
        !@errors.empty?
      end

      def warn?
        !@warnings.empty?
      end

      private

      def validate_subject(subject)
        validate_resource_class(subject)
      end

      def validate_subject_name
        @num_subject_name.select { |subject_name, num_subject_name| num_subject_name > 1 }.each_key do |subject_name|
          add_error(%/Duplicate subject name (#{subject_name}) in model.yaml file./)
        end

        @num_subject_name.each_key do |subject_name|
          if @num_variable.key?(subject_name) && @num_variable[subject_name] == 1
            add_error(%/Duplicate variable name (#{subject_name}) in model.yaml file./)
          end
        end
      end

      def validate_by_object_names
        property_path = {}
        @model.object_names.each do |object_name|
          add_variable_name(object_name)

          path = @model.property_path(object_name).join(' / ')
          triple = @model.find_by_object_name(object_name)
          next if triple.nil?

          key = [triple.subject.name, path]
          if property_path.key?(key)
            property_path[key] << object_name
          else
            property_path[key] = [object_name]
          end
        end

        property_path.each do |key, names|
          next if names.size < 2

          rdf_type_hash = {}
          names.each do |name|
            triple = @model.find_by_object_name(name)
            k = @model.bnode_rdf_types(triple)
            rdf_type_hash[k] = [] unless rdf_type_hash.key?(k)
            rdf_type_hash[k] << name
          end

          rdf_type_hash.each do |k, ns|
            next if ns.size < 2

            add_warning("Multiple object names (#{ns.join(', ')}) are set in the same property path (#{key[1]}).")
          end
        end
      end

      def validate_resource_class(subject)
        return if subject.blank_node?

        add_warning(%/Subject (#{subject.name}) has no rdf:type./) if subject.types.empty?
      end

      def validate_variable
        @num_variable.select { |k, v| v > 1 }.each do |variable_name, num_variable|
          add_error(%/Duplicate variable name (#{variable_name}) in model.yaml file./)
        end
      end

      def add_error(error_message)
        @errors << error_message
      end

      def add_warning(warn_message)
        @warnings << warn_message
      end

      def add_subject_name(subject_name)
        if @num_subject_name.key?(subject_name)
          @num_subject_name[subject_name] += 1
        else
          @num_subject_name[subject_name] = 1
        end
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

class RDFConfig

  class Model

    class SubjectNotFound < StandardError; end
    class SubjectClassNotFound < StandardError; end
    class RDFObjectNotFound < StandardError; end

    attr_reader :subjects, :predicates, :objects, :yaml, :prefix

    def initialize(config_dir)
      @config_dir = config_dir
      @subject_instances = []

      # use @prefix to validate the data model config file
      parse_prefix("#{@config_dir}/prefix.yaml")
      parse_model("#{@config_dir}/model.yaml")

      # shortcut for ordered list of elements
      @subjects = @subject_instances.map(&:name)
      @predicates = {}
      @objects = {}
      @subject_instances.each do |subject|
        @predicates[subject.name] = [] unless @predicates.key?(subject.name)
        @objects[subject.name] = {} unless @objects.key?(subject.name)
        subject.properties.each do |property|
          next if property.predicate.rdf_type?

          property_path = property.property_paths.join(RDFConfig::SPARQL::PROPERTY_PATH_SEPARATOR)
          @predicates[subject.name] << property_path
          @objects[subject.name][property_path] = [] unless @objects[subject.name].key?(property_path)
          @objects[subject.name][property_path] << property.object.name
        end
      end
    end

    def parse_prefix(prefix_config_file)
      @prefix = YAML.load_file(prefix_config_file)
    end

    def parse_model(model_config_file)
      @yaml = YAML.load_file(model_config_file)
      @yaml.each do |subject_hash|
        @subject_instances << RDFConfig::Model::Subject.new(subject_hash, @prefix)
      end
    end

    def parse_sparql
      YAML.load_file("#{@config_dir}/sparql.yaml")
    end

    def parse_endpoint
      YAML.load_file("#{@config_dir}/endpoint.yaml")
    end

    def parse_stanza
      YAML.load_file("#{@config_dir}/stanza.yaml")
    end

    def subject_name?(variable_name)
      @subject_instances.map(&:name).include?(variable_name)
    end

    def subject_by_name(subject_name)
      subjects = @subject_instances.select{ |subject_inst| subject_inst.name == subject_name }
      raise SubjectNotFound, "Subject: #{subject_name} not found." if subjects.empty?

      subjects.first
    end

    def subject_type(subject_name)
      subject_by_name(subject_name).rdf_type
    end

    def subject_by_object_name(object_name)
      subject = nil
      @subject_instances.each do |subject_instance|
        subject_instance.properties.each do |property|
          if property.object.name == object_name
            subject = subject_instance
            break
          end
        end
      end

      if subject.nil?
        raise SubjectNotFound, "Subject with the object name '#{object_name}' does not exist."
      end

      subject
    end

    def subject_name(object_name)
      subject_by_object_name(object_name).name
    end

    def property_by_object_name(object_name)
      rdf_property = nil
      @subject_instances.each do |subject|
        subject.properties.each do |property|
          if property.object.name == object_name
            rdf_property = property
            break
          end
        end
      end

      if rdf_property.nil?
        raise RDFObjectNotFound, "RDF Object: #{object_name} not found."
      end

      rdf_property
    end

    def property_paths(object_name)
      property_by_object_name(object_name).property_paths
    end

    def object_type(object_name)
      rdf_property = property_by_object_name(object_name)
      if @subject_instances.map(&:name).include?(rdf_property.object.value)
        :class
      else
        rdf_property.object.format
      end
    end

    def object_value(object_name)
      property_by_object_name(object_name).object.value
    end

  end
end

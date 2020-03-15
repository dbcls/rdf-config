class RDFConfig

  class Model
    attr_reader :subject_type_map, :predicate_path_map, :object_label_map,
                :subjects, :predicates, :objects

    def initialize(config_dir)
      # mappings for supplimental information
      @subject_type_map = {}
      @predicate_path_map = {}
      @property_paths = []
      @object_label_map = {}

      # shortcut for ordered list of elements
      @subjects = []
      @predicates = {}
      @objects = {}

      # use @prefix to validate the data model config file
      parse_prefix("#{config_dir}/prefix.yaml")
      parse_model("#{config_dir}/model.yaml")
    end

    def parse_prefix(prefix_config_file)
      @prefix = YAML.load_file(prefix_config_file)
    end

    def parse_model(model_config_file)
      model = YAML.load_file(model_config_file)
      model.each do |subject_block|
        proc_subject_block(subject_block)
      end
    end

    def proc_subject_block(subject_block)
      subject_block.each do |subject, property_blocks|
        @current_subject_name = subject.split(/\s+/).at(0)
        @predicate_path_map[@current_subject_name] = {}
        @object_label_map[@current_subject_name] = {}
        property_blocks.each do |property_block|
          if ['a', 'rdf:type'].include?(property_block.keys.at(0))
            @subject_type_map[@current_subject_name] = property_block[property_block.keys.at(0)]
            # shortcut
            @subjects << @current_subject_name
          else
            proc_property_block(property_block)
          end
        end
      end
    end

    def proc_property_block(property_block, reset_property_path = true)
      property_block.each do |predicate, objects|
        #puts "predicate: #{predicate}"
        if reset_property_path
          @property_paths = [predicate]
        else
          @property_paths << predicate
        end

        case objects
        when String
        #puts objects
        when Array
          objects.each do |object_block|
            proc_object_block(object_block)
          end
        end
      end
    end

    def proc_object_block(object_block)
      case object_block
      when String
      when Hash
        object_block.each do |key, value|
          if key.to_s == '[]'
            proc_blank_node(value)
          else
            property_path = @property_paths.join(' / ')
            @predicate_path_map[@current_subject_name][key] = property_path
            @object_label_map[@current_subject_name][key] = value
            # shortcut
            @predicates[@current_subject_name] ||= []
            @predicates[@current_subject_name] << property_path
            @objects[@current_subject_name] ||= {}
            @objects[@current_subject_name][property_path] ||= []
            @objects[@current_subject_name][property_path] << key
          end
        end
      end
    end

    def proc_blank_node(property_blocks)
      property_blocks.each_with_index do |property_block, i|
        @property_paths.pop if i > 0

        proc_property_block(property_block, false)
      end

      @property_paths.pop
    end
  end

end

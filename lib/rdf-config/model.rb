class RDFConfig

  class Model
    attr_reader :model_type_map, :property_path_map

    def initialize(config_dir)
      # read prefix.yaml as well, then validate, provide interface for the data model
      @model_config_file = "#{config_dir}/model.yaml"

      @model_type_map = {}
      @property_path_map = {}
      @property_paths = []

      parse
    end

    def parse
      model = YAML.load_file(@model_config_file)
      model.each do |subject_block|
        proc_subject_block(subject_block)
      end
    end

    def proc_subject_block(subject_block)
      subject_block.each do |subject, property_blocks|
        @current_subject_name = subject.split(/\s+/).at(0)
        @property_path_map[@current_subject_name] = {}
        property_blocks.each do |property_block|
          if ['a', 'rdf:type'].include?(property_block.keys.at(0))
            @model_type_map[@current_subject_name] = property_block[property_block.keys.at(0)]
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
            @property_path_map[@current_subject_name][key] = @property_paths.join(' / ')
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

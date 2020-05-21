class RDFConfig

  class Model
    attr_reader :subject_type_map, :predicate_path_map, :object_label_map,
                :subjects, :predicates, :objects, :yaml, :prefix

    PROPERTY_PATH_SEPARATOR = ' / '.freeze

    def initialize(config_dir)
      # mappings for supplimental information
      @subject_type_map = {}
      @predicate_path_map = {}
      @property_paths = []
      @object_label_map = {}
      @object_type_map = {}

      # shortcut for ordered list of elements
      @subjects = []
      @predicates = {}
      @objects = {}

      # use @prefix to validate the data model config file
      parse_prefix("#{config_dir}/prefix.yaml")
      parse_model("#{config_dir}/model.yaml")

      @config_dir = config_dir
    end

    def parse_prefix(prefix_config_file)
      @prefix = YAML.load_file(prefix_config_file)
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

    def parse_model(model_config_file)
      @yaml = YAML.load_file(model_config_file)
      # ad hoc workaround
      @subjects = @yaml.map{ |x| x.keys.first.split(/\s+/).at(0) }.uniq
      @yaml.each do |subject_block|
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
            #@subjects << @current_subject_name
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
            key = key.chop if key[/(\?|\+|\*)$/]  # work around for var?, var+, var*
            property_path = @property_paths.join(PROPERTY_PATH_SEPARATOR)
            @predicate_path_map[@current_subject_name][key] = property_path
            @object_label_map[@current_subject_name][key] = value
            @object_type_map[key] = determine_object_type(value)
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

    def subject_name(var_name)
      subject_name = ''
      @predicate_path_map.each do |key, pathmap_hash|
        if pathmap_hash.keys.include?(var_name)
          subject_name = key.dup
          break
        end
      end

      subject_name
    end

    def used_prefixes(variable_names)
      prefixes = []

      variable_names.each do |var_name|
        subject_name = subject_name(var_name)
        next if subject_name.to_s.empty?

        rdf_type = @subject_type_map[subject_name].to_s
        predicate = @predicate_path_map[subject_name][var_name].strip
        [rdf_type, predicate].reject(&:empty?).each do |uri_path|
          uri_path.split(PROPERTY_PATH_SEPARATOR).each do |p|
            if /\A(\w+):\w+\z/ =~ p
              prefixes << Regexp.last_match(1) unless prefixes.include?(Regexp.last_match(1))
            end
          end
        end
      end

      prefixes
    end

    def has_prefix?(prefix)
      @prefix.keys.include?(prefix)
    end

    def rdf_type_predicate?(predicate)
      ['a', 'rdf:type'].include?(predicate)
    end

    def blank_node_object?(object)
      case object
      when Array
        true
      when String
        object == '[]'
      else
        false
      end
    end

    def determine_object_type(value)
      case value
      when String
        if @subjects.include?(value)
          :class
        elsif /\A<.+\>\z/ =~ value
          :uri
        else
          if /\A(\w+):/ =~ value && has_prefix?(Regexp.last_match(1))
            :uri
          else
            :literal
          end
        end
      else
        :literal
      end
    end

    def object_type(object_name)
      @object_type_map[object_name]
    end

    def sparql_triple_lines(variable_names)
      subjects = subject_instances

      required_lines = {}
      optional_lines = {}
      variable_names.each do |var_name|
        subject_name = subject_name(var_name)
        next if subject_name.to_s.empty?

        subject = subjects.select { |subj| subj.name == subject_name }.first
        required_lines[subject_name] = [['a', @subject_type_map[subject_name]]] unless required_lines.key?(subject_name)
        optional_lines[subject_name] = [] unless optional_lines.key?(subject_name)

        if @predicate_path_map[subject_name][var_name]
          property = [@predicate_path_map[subject_name][var_name], "?#{var_name}"]
        else
          var_info = find_variable(var_name)
          property_path = "#{@predicate_path_map[subject_name][var_info[:subject_name]]}#{PROPERTY_PATH_SEPARATOR}#{var_info[:path_map]}"
          property = [property_path, "?#{var_name}"]
        end

        property_instance = subject.properties.select { |property| property.object.name == var_name }.first
        object = property_instance.object
        if object.optional
          optional_lines[subject_name] << property
        else
          required_lines[subject_name] << property
        end
      end

      { required: required_lines, optional: optional_lines }
    end

    def subject?(name)
      @subjects.include?(name)
    end

    def subject_instances
      instances = []
      @yaml.each do |subject_hash|
        instances << RDFConfig::Model::Subject.new(subject_hash, @prefix)
      end

      instances
    end

  end
end

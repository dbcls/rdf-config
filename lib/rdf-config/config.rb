require 'yaml'
require 'pathname'

class RDFConfig
  class Config
    CONFIG_NAMES = %i[model sparql prefix endpoint stanza metadata schema convert].freeze

    CONFIG_NAMES.each do |name|
      define_method name do
        begin
          instance_varname = "@#{name}"
          instance_variable_get(instance_varname) ||
            instance_variable_set(instance_varname, read_config(config_file_path(name)))
        rescue Psych::SyntaxError => e
          raise SyntaxError, "Invalid YAML format #{e.message}"
        end
      end
    end

    attr_reader :config_dir

    def initialize(config_dir, opts = {})
      config_dirs = if config_dir.is_a?(Array)
                      config_dir
                    else
                      [config_dir.to_s]
                    end

      not_found_config_dirs = []
      config_dirs.each do |dir_path|
        not_found_config_dirs << dir_path unless File.exist?(dir_path)
      end
      unless not_found_config_dirs.empty?
        raise ConfigNotFound, "Config directory (#{not_found_config_dirs.join(', ')}) does not exist."
      end

      @config_dir = config_dir
      @opts = opts
    end

    def exist?(name)
      config_file_path(name)
      true
    rescue ConfigNotFound
      false
    end

    def name
      File.basename(@config_dir)
    end

    def absolute_path(config_file_path)
      File.expand_path(config_file_path, @config_dir)
    end

    private

    def config_file_path(name)
      fpath = Pathname.new(@config_dir).join("#{name}.yaml").to_path
      raise ConfigNotFound, "Config file (#{fpath}) does not exist." unless File.exist?(fpath)

      fpath
    end

    def read_config(config_file_path)
      config = if Gem::Version.create(RUBY_VERSION) >= Gem::Version.create('3.1')
                 require 'date'
                 YAML.load_file(config_file_path, permitted_classes: [Date, Time, Symbol])
               else
                 YAML.load_file(config_file_path)
               end

      if !config.is_a?(Hash) && !config.is_a?(Array)
        raise InvalidConfig, "Config file (#{config_file_path}) is not a valid YAML file."
      end

      case config
      when Hash
        convert_symbol_to_string(config)
      when Array
        config.map { |subject_config| convert_symbol_to_string(subject_config) }
      else
        config
      end
    end

    def convert_symbol_to_string(src_hash)
      return src_hash unless src_hash.is_a?(Hash)

      to_hash = src_hash.transform_keys { |key| key.is_a?(Symbol) ? ":#{key}" : key }
      to_hash.each do |key, value|
        case value
        when Hash
          convert_symbol_to_string(value)
        when Array
          value.map! { |v| convert_symbol_to_string(v) }
        when Symbol
          to_hash[key] = ":#{value}"
        else
          value
        end
      end

      to_hash
    end

    class ConfigNotFound < StandardError; end
    class SyntaxError < StandardError; end
    class InvalidConfig < StandardError; end
  end
end

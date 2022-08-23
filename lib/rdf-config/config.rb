require 'yaml'
require 'pathname'

class RDFConfig
  class Config
    CONFIG_ROOT_DIR = 'config'.freeze
    CONFIG_TYPES = %i[model sparql prefix endpoint stanza metadata schema].freeze

    CONFIG_TYPES.each do |name|
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

    class << self
      def config_names(config_root_dir = CONFIG_ROOT_DIR)
        Dir.entries(config_root_dir).reject { |name| name.length.positive? && name[0] == '.' }
           .select { |name| File.directory?(File.join(config_root_dir, name)) }
           .sort
      end
    end

    attr_reader :config_dir

    def initialize(config_dir, opts = {})
      config_dirs = if config_dir.is_a?(Array)
                      config_dir.map { |dir_name| File.expand_path(dir_name) }
                    else
                      [File.expand_path(config_dir)]
                    end

      not_found_config_dirs = []
      config_dirs.each do |dir_path|
        not_found_config_dirs << dir_path unless File.exist?(dir_path)
      end
      unless not_found_config_dirs.empty?
        raise ConfigNotFound, "Config directory (#{not_found_config_dirs.join(', ')}) does not exist."
      end

      @config_dir = config_dirs.size == 1 ? config_dirs.first : config_dirs
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

    private

    def config_file_path(name)
      fpath = Pathname.new(@config_dir).join("#{name}.yaml").to_path
      raise ConfigNotFound, "Config file (#{fpath}) does not exist." unless File.exist?(fpath)

      fpath
    end

    def read_config(config_file_path)
      config = if Gem::Version.create(RUBY_VERSION) >= Gem::Version.create('3.1')
                 require 'date'
                 YAML.load_file(config_file_path, permitted_classes: [Date, Time])
               else
                 YAML.load_file(config_file_path)
               end

      if !config.is_a?(Hash) && !config.is_a?(Array)
        raise InvalidConfig, "Config file (#{config_file_path}) is not a valid YAML file."
      end

      config
    end

    class ConfigNotFound < StandardError; end
    class SyntaxError < StandardError; end
    class InvalidConfig < StandardError; end
  end
end

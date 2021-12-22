require 'yaml'
require 'pathname'

class RDFConfig
  class Config
    CONFIG_NAMES = %i[model sparql prefix endpoint stanza metadata schema].freeze

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
      raise ConfigNotFound, "Config directory (#{config_dir}) does not exist." unless File.exist?(config_dir)

      @config_dir = config_dir
      @opts = opts
    end

    def exist?(name)
      config_file_path(name)
      true
    rescue ConfigNotFound
      false
    end

    private

    def config_file_path(name)
      fpath = Pathname.new(@config_dir).join("#{name}.yaml").to_path
      raise ConfigNotFound, "Config file (#{fpath}) does not exist." unless File.exist?(fpath)

      fpath
    end

    def read_config(config_file_path)
      config = YAML.load_file(config_file_path)
      raise InvalidConfig, "Config file (#{config_file_path}) is not a valid YAML file." if !config.is_a?(Hash) && !config.is_a?(Array)

      config
    end

    class ConfigNotFound < StandardError; end
    class SyntaxError < StandardError; end
    class InvalidConfig < StandardError; end
  end
end

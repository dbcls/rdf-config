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
            instance_variable_set(instance_varname, YAML.load_file(config_file_path(name)))
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

    private

    def config_file_path(name)
      fpath = Pathname.new(@config_dir).join("#{name}.yaml").to_path
      raise ConfigNotFound, "Config file (#{fpath}) does not exist." unless File.exist?(fpath)

      fpath
    end

    class ConfigNotFound < StandardError; end
    class SyntaxError < StandardError; end
    class InvalidConfig < StandardError; end
  end
end

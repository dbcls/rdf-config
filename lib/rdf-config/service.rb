require_relative 'config'
require_relative 'model'

class RDFConfig
  class Service
    class VersionNotSupported < StandardError; end

    LEAST_SUPPORT_VERSION = '2.5'.freeze

    def initialize(config, opts)
      # TODO: Hash#transform_keys is supported from version 2.5
      if Gem::Version.create(RUBY_VERSION) < Gem::Version.create(LEAST_SUPPORT_VERSION)
        raise VersionNotSupported, "This program supported over Ruby version #{LEAST_SUPPORT_VERSION}"
      end

      @config = config
      @model = Model.instance(config)
      @opts = opts.transform_keys(&:to_sym)
    end

    def [](opts_key)
      @opts[opts_key.to_sym]
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  service_name = 'refex'
  config_dir = File.join(ENV['HOME'], 'github', 'dbcls', 'rdf-config', 'config', service_name)
  opts = {
    'mode' => 'grasp',
    'hoge' => 'hoge',
    'fuga' => 'fuga'
  }

  config = RDFConfig::Config.new(config_dir, opts)
  service = RDFConfig::Service.new(config, opts)
  puts service[:mode]
end

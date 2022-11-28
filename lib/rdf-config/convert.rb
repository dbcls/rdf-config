require_relative 'convert/method_parser'
require_relative 'convert/converter'
require_relative 'convert/rdf_generator'

class RDFConfig
  class Convert
    SOURCE_FORMATS = %w[csv tsv json xml].freeze

    def initialize(config, opts)
      @config = config
      @source = opts[:input_file]

      @source_file_format = nil
      @convert_method = {}
      @rows = []

      @json_paths = []
    end

    def generate
      parse_convert_config
      read_source_file
      generate_rdf
    end

    def parse_convert_config
      method_parser = MethodParser.new

      @config.convert.each do |variable_name, converters|
        @convert_method[variable_name] = [] unless @convert_method.key?(variable_name)

        converters = [converters] if converters.is_a?(String)
        converters.each do |converter|
          method = method_parser.parse(converter)
          if @source_file_format.nil? && SOURCE_FORMATS.include?(method[:method_name_])
            @source_file_format = method[:method_name_]
          end
          @convert_method[variable_name] << method

          if method[:method_name_] == 'json'
            @json_paths << method[:args_][:arg_].to_str[1..-2].split(%r{\s*/\s*})[0..-2].join('/')
          end
        end
      end

      @json_paths.uniq!
    end

    def read_source_file(**opts)
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/file_reader/csv_reader'
        @rows = CsvReader.new(@source, @source_file_format).read
      when 'json'
        require_relative 'convert/file_reader/json_reader'
        reader = JSONReader.new(@source)
        @rows = reader.read(@json_paths.first)
      when 'xml'
      end
    end

    def generate_rdf
      generator = RDFGenerator.new(
        Converter.new(@convert_method), @rows, Model.instance(@config), @config.prefix
      )
      generator.generate
    end
  end
end

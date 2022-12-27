require_relative 'convert/method_parser'
require_relative 'convert/rdf_generator'

class RDFConfig
  class Convert
    SOURCE_FORMATS = %w[csv tsv json xml].freeze

    def initialize(config, opts)
      @config = config
      @source = opts[:input_file]

      @source_file_format = nil
      @convert_method = {}
    end

    def generate
      parse_convert_config
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
        end
      end
    end

    def generate_rdf
      rdf_generator.generate
    end

    def file_reader
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/file_reader/csv_reader'
        CSVReader.new(@source, @source_file_format)
      when 'json'
        require_relative 'convert/file_reader/json_reader'
        JSONReader.new(@source)
      when 'xml'
        require_relative 'convert/file_reader/xml_reader'
        XMLReader.new(@source)
      end
    end

    def rdf_generator
      case @source_file_format
      when 'csv', 'tsv'
        require_relative 'convert/converter/csv_converter'
        require_relative 'convert/rdf_generator/csv2rdf'
        CSV2RDF.new(@config, file_reader, CSVConverter.new(@convert_method))
      when 'json'
        require_relative 'convert/converter/json_converter'
        require_relative 'convert/rdf_generator/json2rdf'
        JSON2RDF.new(@config, file_reader, JSONConverter.new(@convert_method))
      when 'xml'
        require_relative 'convert/converter/xml_converter'
        require_relative 'convert/rdf_generator/xml2rdf'
        XML2RDF.new(@config, file_reader, XMLConverter.new(@convert_method))
      end
    end
  end
end

# frozen_string_literal: true

class RDFConfig
  class ModelGenerator
    class UnsupportedFormat < StandardError; end

    DEFAULT_INPUT_FORMAT = 'void'

    def initialize(**opts)
      @input_format = opts[:input] || DEFAULT_INPUT_FORMAT
      @input_format = @input_format[1..-1] if @input_format.start_with?(':')

      @output_dir = opts[:output].first
      @input_file = opts[:output].last
    end

    def generate
      generator.generate
    end

    def generator
      case @input_format
      when 'void'
        require_relative 'model_generator/void'
        Void.new(@input_file, @input_format, @output_dir)
      else
        raise UnsupportedFormat, %(Format "#{@input_format}" is not supported.)
      end
    end
  end
end

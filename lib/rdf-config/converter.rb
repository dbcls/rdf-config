require 'csv'
require 'rdf/turtle'

class RDFConfig
  class Converter
    attr_reader :value

    def initialize(config, opts)
      @model = Model.new(config)
      @prefixes = config.prefix.map { |prefix, uri| [prefix, RDF::URI.new(uri[1..-2])] }.to_h
      @convert = config.convert
      @source = opts[:input_file]

      @row = nil
      @v = []
      @value = {}

      @line_no = 1
    end

    def convert
      RDF::Writer.for(:turtle).new(prefixes: @prefixes, canonicalize: true) do |writer|
        CSV.foreach(@source, col_sep: "\t", headers: :first_row) do |row|
          @row = row
          process_row
          generate_rdf(writer)

          @line_no += 1
          break if @line_no > 10
        end
      end
    end

    def generate_rdf(writer)
      done_subject_types = []
      @value.each do |variable_name, v|
        if v.is_a?(Array)
          values = v
        else
          values = [v]
        end

        rdf_types = []
        if @model.subject?(variable_name) && !done_subject_types.include?(variable_name)
          @model.find_subject(variable_name).types.each do |rdf_type|
            prefix, local_part = rdf_type.split(':', 2)
            if @prefixes.key?(prefix)
              rdf_types << RDF::URI.new("#{@prefixes[prefix].to_s}#{local_part}")
            else
              rdf_types << RDF::URI.new(rdf_type)
            end
          end
        end

        values.each do |value|
          triple = @model.find_by_object_name(variable_name)
          next if triple.nil?

          subject_name = triple.subject.name
          next unless @value.keys.include?(subject_name)

          subject_value = @value[subject_name]
          if subject_value.is_a?(Array)
            subject_value = subject_value[0]
          end
          prefix, local_part = subject_value.split(':', 2)
          if @prefixes.key?(prefix)
            subject_value = "#{@prefixes[prefix].to_s}#{local_part}"
          end
          subject_node = RDF::URI.new(subject_value)

          predicate_uri = triple.predicate.uri
          prefix, local_part = predicate_uri.split(':', 2)
          if @prefixes.key?(prefix)
            predicate_uri = "#{@prefixes[prefix].to_s}#{local_part}"
          end
          predicate_node = RDF::URI.new(predicate_uri)

          case triple.object
          when Model::Literal
            object_node = RDF::Literal.new(value)
          when Model::URI
            object_node = RDF::URI.new(value)
          when Model::Subject
            object_node = RDF::URI.new(value)
          when Model::ValueList
            object_node = RDF::URI.new(value)
          end

          unless done_subject_types.include?(subject_name)
            @model.find_subject(subject_name).types.each do |rdf_type|
              prefix, local_part = rdf_type.split(':', 2)
              if @prefixes.key?(prefix)
                writer <<
                  RDF::Statement.new(subject_node, RDF.type, RDF::URI.new("#{@prefixes[prefix].to_s}#{local_part}"))
              else
                writer <<
                  RDF::Statement.new(subject_node, RDF.type, RDF::URI.new(rdf_type))
              end
            end
            done_subject_types << subject_name
          end
          writer << RDF::Statement.new(subject_node, predicate_node, object_node)
        end
      end
    end

    def process_row
      @convert.each do |variable_name, converters|
        @v = @row
        exec_process(converters)
        @value[variable_name] = @v
      end
    end

    def exec_process(converters)
      if converters.is_a?(String)
        converters = [converters]
      end

      converters.each do |converter|
        /\A\$(?<name>\w+)(\((?<args>.*)\))?\z/ =~ converter
        if args.nil?
          args = ''
        else
          args = args.split(/\s*,\s*/).map { |v| v.gsub(/\A"(.+)"\z/) { $1 } }
        end

        unless respond_to?(name)
          require_relative "converter/#{name}.rb"
          self.class.define_method(name.to_sym, self.class.instance_method(name.to_sym))
        end

        exec_converter(name, *args)
      end
    end

    def exec_converter(name, *args)
      if @v.is_a?(Array)
        @v = @v.map { |v| send(name, v, *args) }
      else
        @v = send(name, @v, *args)
      end
    end
  end
end

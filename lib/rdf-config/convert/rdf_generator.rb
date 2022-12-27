# frozen_string_literal: true
require 'rdf/turtle'

class RDFConfig
  class Convert
    class RDFGenerator
      def initialize(config, reader, converter)
        @config = config
        @reader = reader
        @converter = converter

        @model = Model.instance(@config)
        @prefixes = @config.prefix.transform_values { |uri| RDF::URI.new(uri[1..-2]) }
        @prefixes[:xsd] = RDF::URI.new('http://www.w3.org/2001/XMLSchema#')

        @statements = []
        @subject_node = {}
      end

      def generate
        generate_statements
        output_rdf
      end

      def generate_statements
        @converter.root_paths.each do |path|
          @reader.each_row(path) do |row|
            parent_subject_node = generate_statements_by_row(row, nil, *@converter.path_variable_map[path])
            next unless @converter.path_relation.key?(path)

            @converter.path_relation[path].each do |child_path|
              @reader.each_row(relative_path(path, child_path)) do |child_row|
                generate_statements_by_row(child_row, parent_subject_node, *@converter.path_variable_map[child_path])
              end
            end
          end
        end
      end

      def output_rdf
        RDF::Writer.for(:turtle).new(prefixes: @prefixes, canonicalize: true) do |writer|
          @statements.each do |statement|
            writer << statement
          end
        end
      end

      private

      def generate_statements_by_row(row, parent, *variable_names)
        subject_name, subject = subject_node(row, *variable_names)

        variable_names.each do |variable_name|
          next if variable_name == subject_name

          triple = @model.find_by_object_name(variable_name)
          if triple.subject.name != subject_name && triple.predicates.size == 1
            subject = subject_node_by_subject_name(row, triple.subject.name)
            parent = nil
          end

          @converter.clear_value
          converted_value = @converter.convert_value(row, variable_name)
          triple = @model.find_by_object_name(variable_name)
          object_node = object_node_by_triple(triple, converted_value)
          next if object_node.nil?
          
          @statements << RDF::Statement.new(
            subject,
            predicate_node(triple.predicates.last.uri),
            object_node_by_triple(triple, converted_value)
          )
        end

        if parent
          triple = @model.find_by_object_name(subject_name || variable_names.first)
          @statements << RDF::Statement.new(
            parent,
            predicate_node(triple.predicates.last.uri),
            subject
          )
        end

        subject
      end

      def subject_node(row, *variable_names)
        @converter.clear_value

        subject_name = variable_names.select { |name| @model.subject?(name) }.first
        if subject_name
          subject = subject_node_by_subject_name(row, subject_name)
          @subject_node[subject_name] = subject
          [subject_name, subject]
        else
          [nil, RDF::Node.new]
        end
      end

      def subject_node_by_subject_name(row, subject_name)
        # return @subject_node[subject_name] if @subject_node.key?(subject_name)

        converted_value = @converter.convert_value(row, subject_name)
        subject = uri_node(converted_value)
        # @subject_node[subject_name] = subject

        @model.find_subject(subject_name).types.each do |rdf_type|
          @statements << RDF::Statement.new(subject, RDF.type, uri_node(rdf_type))
        end

        subject
      end

      def predicate_node(predicate_uri)
        prefix, local_part = predicate_uri.split(':', 2)
        predicate_uri = "#{@prefixes[prefix].to_s}#{local_part}" if @prefixes.key?(prefix)

        RDF::URI.new(predicate_uri)
      end

      def object_node_by_triple(triple, object_value)
        return nil if object_value.to_s.empty?
        
        case triple.object
        when Model::Literal
          literal_node(object_value, triple.object)
        when Model::URI
          uri_node(object_value)
        when Model::ValueList
          uri_node(object_value)
        else
          nil
        end
      end

      def uri_node(uri)
        prefix, local_part = uri.split(':', 2)
        if @prefixes.key?(prefix)
          RDF::URI.new("#{@prefixes[prefix].to_s}#{local_part}")
        else
          RDF::URI.new(uri)
        end
      end

      def literal_node(value, literal_object)
        case literal_object.value
        when Integer
          RDF::Literal::Integer.new(value)
        when Float
          # RDF::Literal.new(value.to_f)
          RDF::Literal::Decimal.new(value)
        when Date
          RDF::Literal::Date.new(value)
        when TrueClass, FalseClass
          RDF::Literal::Boolean.new(value)
        else
          RDF::Literal.new(value)
        end
      end

      def relative_path(parent_path, child_path)
        child_path[(parent_path.length + 1)..]
      end

      def subject_names
        @converter.variable_names.select { |variable_name| @model.subject?(variable_name) }
      end

      def object_names
        @converter.variable_names.reject { |variable_name| @model.subject?(variable_name) }
      end
    end
  end
end

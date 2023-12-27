# frozen_string_literal: true

require 'rdf/turtle'

class RDFConfig
  class Convert
    class RDFGenerator
      def initialize(config, convert)
        @config = config
        @convert = convert
        @reader = nil
        @converter = convert.rdf_converter

        @model = Model.instance(@config)
        @prefixes = @config.prefix.transform_values { |uri| RDF::URI.new(uri[1..-2]) }
        @prefixes[:xsd] = RDF::URI.new('http://www.w3.org/2001/XMLSchema#')

        @statements = []
        @subject_stack = []
      end

      def generate
        generate_statements
        output_rdf
      end

      def generate_statements
        @convert.root_subjects.each do |subject_name|
          generate_statements_by_subject_name(subject_name, root: true)
        end
      end

      def output_rdf
        RDF::Writer.for(:turtle).new(**rdf_writer_opts) do |writer|
          @statements.each do |statement|
            writer << statement
          end
        end
      end

      private

      def generate_statements_by_subject_name(subject_name, root: false)
        @reader.each_row(path_by_convert_def(subject_name), is_subject_node: true) do |row|
          @converter.push_target_row(row)

          process_convert_variable(row)

          subject = subject_node(row, subject_name)
          @subject_stack.push(subject)

          subject_names = @convert.subject_object_map[subject_name].select { |name| @model.subject?(name) || @convert.bnode_name?(name) }
          object_names = @convert.subject_object_map[subject_name] - subject_names
          generate_statements_by_row(row, subject, *object_names)

          subject_names.each do |subj_name|
            generate_statements_by_subject_name(subj_name)
          end

          generate_relation_statement(subject_name) unless root

          @subject_stack.pop
          @converter.pop_target_row
        end
      end

      def generate_statements_by_row(row, subject, *variable_names)
        variable_names.each do |variable_name|
          generate_statement_by_variable_name(row, subject, variable_name)
        end
      end

      def generate_relation_statement(object_name)
        predicate_uri = if @convert.bnode_name?(object_name)
                          triple = @model.find_by_object_name(@convert.subject_object_map[object_name].first)
                          triple.predicates.first.uri
                        else
                          triple = @model.find_by_object_name(object_name)
                          triple.predicates.last.uri
                        end
        @statements << RDF::Statement.new(
          @subject_stack[-2], predicate_node(predicate_uri), @subject_stack.last
        )
      end

      def generate_statement_by_variable_name(row, subject, variable_name)
        @converter.clear_value
        converted_value = @converter.convert_value(row, variable_name)
        return if converted_value.is_a?(String) && converted_value.strip.empty?

        triple = @model.find_by_object_name(variable_name)
        @statements << RDF::Statement.new(
          subject,
          predicate_node(triple.predicates.last.uri),
          object_node_by_triple(triple, converted_value)
        )
      end

      def process_convert_variable(row)
        @converter.convert_variable_names.each do |variable_name|
          @converter.convert_value(row, variable_name)
        end
      end

      def subject_node(row, subject_name)
        @converter.clear_value

        if @convert.bnode_name?(subject_name)
          RDF::Node.new
        else
          subject_node_by_subject_name(row, subject_name)
        end
      end

      def subject_node_by_subject_name(row, subject_name)
        converted_value = @converter.convert_value(row, subject_name)
        subject = uri_node(converted_value)

        @model.find_subject(subject_name).types.each do |rdf_type|
          @statements << RDF::Statement.new(subject, RDF.type, uri_node(rdf_type))
        end

        subject
      end

      def predicate_node(predicate_uri)
        uri_node(predicate_uri)
      end

      def object_node_by_triple(triple, object_value)
        case triple.object
        when Model::Subject
          uri_node(object_value)
        when Model::Literal
          literal_node(object_value, triple.object)
        when Model::URI
          uri_node(object_value)
        when Model::ValueList
          if triple.object.value.first.is_a?(Model::Literal)
            literal_node(object_value, triple.object)
          else
            uri_node(object_value)
          end
        end
      end

      def uri_node(uri)
        prefix, local_part = uri.to_s.split(':', 2)
        if @prefixes.key?(prefix)
          RDF::URI.new("#{@prefixes[prefix]}#{local_part}")
        else
          RDF::URI.new(uri)
        end
      end

      def literal_node(value, literal_object)
        return value if value.is_a?(RDF::Literal)

        case literal_object.value
        when String
          literal_node_by_string_value(value, literal_object)
        when Integer
          RDF::Literal::Integer.new(value)
        when Float
          RDF::Literal::Decimal.new(value)
        when Date
          RDF::Literal::Date.new(value)
        when TrueClass, FalseClass
          RDF::Literal::Boolean.new(to_bool(value))
        else
          RDF::Literal.new(value)
        end
      end

      def literal_node_by_string_value(value, literal_object)
        if /.+\^\^(.+)\z/ =~ literal_object.value
          prefix, local_part = $1.split(':', 2)
          if prefix == 'xsd'
            RDF::Literal.new(value, datatype: eval("RDF::XSD.#{local_part}"))
          else
            # TODO Other datatype or lang tag
            RDF::Literal.new(value)
          end
        else
          RDF::Literal.new(value)
        end
      end

      def to_bool(value)
        !['0', 'f', 'false', ''].include?(value.to_s.strip.downcase)
      end

      def rdf_writer_opts
        {
          prefixes: @prefixes,
          canonicalize: false
        }
      end
    end
  end
end

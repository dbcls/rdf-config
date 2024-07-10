# frozen_string_literal: true

require 'rdf/turtle'
require_relative 'generator'

class RDFConfig
  class Convert
    class RDFGenerator < Generator
      def initialize(config, convert)
        super

        @statements = []
        @subject_stack = []
      end

      def generate
        generate_statements
        output_rdf
      end

      def generate_statements
        @convert.subject_converts.each do |subject_convert|
          generate_statements_by_subject(subject_convert, root: true)
        end
      end

      def output_rdf
        RDF::Writer.for(:turtle).new(**rdf_writer_opts) do |writer|
          refined_statements.each do |statement|
            writer << statement
          end
        end
      end

      private

      def generate_subject(subject_name, subject_value = nil)
        subject = @model.find_subject(subject_name)
        node = if subject_value.nil?
                 RDF::Node.new
               elsif subject&.blank_node?
                 RDF::Node.new(subject_value)
               else
                 uri_node(subject_value)
               end
        add_subject_node(subject_name, node)
        add_subject_type_node(subject_name, node)
      end

      def generate_bnode_subject(subject_name)
        generate_subject(subject_name)
      end

      def generate_statements_by_subject(subject_convert, root: false)
        subject_name = subject_convert.keys.first
        @reader.each_row(path_by_convert_def(subject_name), is_subject_node: true) do |row|
          @converter.push_target_row(row)

          process_convert_variable(row)

          subject = subject_node(row, subject_name)
          @subject_stack.push(subject)

          subject_names = @convert.subject_object_map[subject_name].select { |name| @model.subject?(name) || @convert.bnode_name?(name) }
          object_names = @convert.subject_object_map[subject_name] - subject_names
          generate_statements_by_row(row, subject, *object_names)

          subject_names.each do |subj_name|
            generate_statements_by_subject(subj_name)
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

      def subject_node(row, subject_name)
        @converter.clear_value

        if @convert.bnode_name?(subject_name)
          RDF::Node.new
        else
          subject_node_by_subject_name(row, subject_name)
        end
      end

      def add_subject_type_node(subject_name, subject)
        @model.find_subject(subject_name).types.each do |rdf_type|
          @statements << RDF::Statement.new(subject, RDF.type, uri_node(rdf_type))
        end
      end

      def subject_node_by_subject_name(row, subject_name)
        converted_value = @converter.convert_value(row, subject_name)
        uri_node(converted_value)
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
        when Model::Unknown
          literal_node(object_value, triple.object)
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
          canonicalize: false,
          unique_bnodes: true,
          stream: false
        }
      end

      def refined_statements
        subject_uris = @statements.map(&:subject).map(&:to_s).uniq
        subject_uris_for_output = subject_uris.select do |subject_uri|
          statements = @statements.select { |statement| statement.subject.to_s == subject_uri }
          statements.select { |statement| statement.subject.to_s == subject_uri }
                    .reject { |statement| statement.predicate == RDF.type }.size.positive?
        end

        @statements.select { |statement| subject_uris_for_output.include?(statement.subject.to_s) }
      end
    end
  end
end

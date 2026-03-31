# frozen_string_literal: true

require 'json'
require 'rdf/turtle'
require_relative 'generator'
require_relative '../../../rust/rust_rdf_turtle/rust_rdf_turtle'

class RDFConfig
  class Convert
    class RDFGenerator < Generator
      def initialize(config, convert)
        super

        @rdf_format = @convert.format.start_with?(':') ? @convert.format[1..-1] : @convert.format

        @statements = []
        @subject_stack = []

        @one_row_statements = []
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
        # statements = @statements.flatten.uniq
        # @statements = []

        # return if statements.empty?

        # rdf = RDF::Writer.for(@rdf_format.to_sym).buffer(**rdf_writer_opts) do |writer|
        #   statements.each do |statement|
        #     writer << statement
        #   end
        # end

        @intermediate_statements.uniq!

        # Todo: Ignore HGNC invalid IRI
        @intermediate_statements.reject! do |statement|
          statement[:type] == 'triple' && (statement[:s].include?('|') || statement[:o].to_s.include?('|'))
        end

        rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        rdf_type_only_subjects = @intermediate_statements.group_by { |h| h[:s] }
                                                         .select { |_s, group| group.all? { |h| h[:p] == rdf_type } }
                                                         .keys
        @intermediate_statements = @intermediate_statements.reject do |h|
          rdf_type_only_subjects.include?(h[:s]) || rdf_type_only_subjects.include?(h[:o])
        end

        if false
          rust_rdf_prog = File.join(__dir__, '..', '..', '..', 'rust/rust_rdf_turtle_prog/target/release/ttl_writer')
          rdf = IO.popen([rust_rdf_prog], 'r+') do |io|
            intermediate_prefixes.each do |prefix|
              io.puts prefix.to_json
            end

            @intermediate_statements.each do |statement|
              io.puts statement.to_json
            end

            io.close_write
            io.read
          end
        else
          rdf = RustRdfTurtle.generate_turtle(@intermediate_statements)
        end

        init_intermediate_prefixes

        rdf = reject_prefix_lines(rdf) if turtle_format?
        puts rdf
      end

      def turtle_format?
        @rdf_format.to_s == 'turtle'
      end

      def ntriples_format?
        @rdf_format.to_s == 'ntriples'
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
        add_subject_type_node(subject_name, node) unless @convert.has_rdf_type_object?
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
        @one_row_statements << RDF::Statement.new(
          @subject_stack[-2], predicate_node(predicate_uri), @subject_stack.last
        )
      end

      def generate_statement_by_variable_name(row, subject, variable_name)
        @converter.clear_value
        converted_value = @converter.convert_value(row, variable_name)
        return if converted_value.is_a?(String) && converted_value.strip.empty?

        triple = @model.find_by_object_name(variable_name)
        @one_row_statements << RDF::Statement.new(
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
          # @one_row_statements << {
          #   statement: RDF::Statement.new(subject, RDF.type, uri_node(rdf_type)),
          #   triple: nil
          # }
          @intermediate_statements << {
            type: 'triple',
            s_kind: 'iri',
            s: subject,
            p: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
            o_kind: 'iri',
            o: uri_node(rdf_type)
          }
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
          # uri_node(object_value)
          { o_kind: 'iri', o: object_value }
        when Model::Literal
          literal_node(object_value, triple.object)
        when Model::URI
          # uri_node(object_value)
          { o_kind: 'iri', o: object_value }
        when Model::ValueList
          if triple.object.first_instance.is_a?(Model::Literal)
            literal_node(object_value, triple.object)
          else
            # uri_node(object_value)
            { o_kind: 'iri', o: object_value }
          end
        when Model::Unknown
          literal_node(object_value, triple.object)
        end
      end

      def uri_node(uri)
        prefix, local_part = uri.to_s.split(':', 2)
        if @prefixes.key?(prefix)
          # RDF::URI.new("#{@prefixes[prefix]}#{local_part}")
          "#{@prefixes[prefix]}#{local_part}"
        else
          # RDF::URI.new(uri)
          uri
        end
      end

      def literal_node(value, literal_object)
        return value if value.is_a?(RDF::Literal)

        case literal_object.value
        when String
          literal_node_by_string_value(value, literal_object)
        when Integer
          # RDF::Literal::Integer.new(value)
          # { o_kind: 'literal_plain', o: Integer(value) }
          { o_kind: 'literal_dt', o: value, datatype: 'http://www.w3.org/2001/XMLSchema#integer' }
        when Float
          # RDF::Literal::Decimal.new(value)
          # { o_kind: 'literal_plain', o: Float(value) }
          { o_kind: 'literal_dt', o: value, datatype: 'http://www.w3.org/2001/XMLSchema#decimal' }
        when Date
          # RDF::Literal::Date.new(value)
          { o_kind: 'literal_dt', o: value, datatype: 'http://www.w3.org/2001/XMLSchema#date' }
        when TrueClass, FalseClass
          # RDF::Literal::Boolean.new(to_bool(value))
          { o_kind: 'literal_dt', o: value, datatype: 'http://www.w3.org/2001/XMLSchema#boolean' }
        else
          # RDF::Literal.new(value)
          { o_kind: 'literal_plain', o: value }
        end
      end

      def literal_node_by_string_value(value, literal_object)
        if /.+\^\^(.+)\z/ =~ literal_object.value
          prefix, local_part = $1.split(':', 2)
          if prefix == 'xsd'
            # RDF::Literal.new(value, datatype: eval("RDF::XSD.#{local_part}"))
            { o_kind: 'literal_dt', o: value, datatype: "http://www.w3.org/2001/XMLSchema##{local_part}" }
          else
            # TODO Other datatype or lang tag
            # RDF::Literal.new(value)
            { o_kind: 'literal_plain', o: value }
          end
        else
          # RDF::Literal.new(value)
          { o_kind: 'literal_plain', o: value }
        end
      end

      def rdf_writer_opts
        {
          prefixes: @prefixes,
          canonicalize: false,
          unique_bnodes: true,
          stream: false
        }
      end

      def refine_statements
        remove_subject_uris = rdftype_only_subject_uris
        until rdftype_only_subject_uris.empty?
          remove_rdftype_only_statemtns(remove_subject_uris)
          remove_no_connection_statements(subject_uris)
          remove_subject_uris = rdftype_only_subject_uris
        end
      end

      def rdftype_only_subject_uris
        subject_uris.select do |subject_uri|
          @one_row_statements.select { |statement| statement[:statement].subject.to_s == subject_uri }
                             .reject { |statement| statement[:statement].predicate == RDF.type }
                             .empty?
        end
      end

      def remove_rdftype_only_statemtns(remove_subject_uris)
        @one_row_statements.reject! { |statement| remove_subject_uris.include?(statement[:statement].subject.to_s) }
      end

      def remove_no_connection_statements(valid_subject_uris)
        @one_row_statements.reject! { |statement| remove_statement?(statement, valid_subject_uris) }
      end

      def remove_statement?(statement, valid_subject_uris)
        return false if statement[:triple].nil?

        triple_object = if statement[:triple].object.is_a?(Model::ValueList)
                          statement[:triple].object.first_instance
                        else
                          statement[:triple].object
                        end
        return false unless triple_object.is_a?(Model::Subject)

        object = statement[:statement].object
        statement[:statement].predicate != RDF.type &&
          (object.is_a?(RDF::URI) || object.is_a?(RDF::Node)) &&
          !valid_subject_uris.include?(object.to_s)
      end

      def subject_uris
        @one_row_statements.map { |statement| statement[:statement].subject }.map(&:to_s).uniq
      end

      def add_statements_for_row
        refine_statements

        @one_row_statements.each do |statement|
          if !statement[:triple].nil? && statement[:triple].predicates.size > 1
            property_path_statements(statement).each do |rdf_statement|
              add_statement(rdf_statement)
            end
          else
            add_statement(statement[:statement])
          end

          object_subjects = if statement[:triple]&.object.is_a?(Model::Subject)
                              [statement[:triple].object]
                            elsif statement[:triple].is_a?(Model::ValueList)
                              statement[:triple].object.value.select { |object| object.is_a?(Model::Subject) }
                            else
                              []
                            end
          object_subjects.each do |object_subject|
            triples = @model.rdf_type_triples_by_subject_name(object_subject.name)
            triples.each do |triple|
              next if @convert.subject_names.include?(triple.subject.name)

              add_statement(
                RDF::Statement.new(@statements.last.object, RDF.type, uri_node(triple.object.value))
              )
            end
          end
        end

        @one_row_statements = []
      end

      def property_path_statements(statement)
        statements = []

        predicates = statement[:triple].predicates
        paths =
          (1...predicates.length).map { |i| predicates[0...i].map(&:uri).join('/') }

        subject = statement[:statement].subject
        paths.each do |path|
          num_paths = path.split(/\s*\/\s*/).size
          object_bnode = bnode_by_bnode_key(bnode_key(statement[:statement].subject, path))
          statements << RDF::Statement.new(
            subject,
            predicate_node(path.split(/\s*\/\s*/).last),
            object_bnode
          )

          types = predicates[num_paths-1].objects.first.values.first.select { |h| h.key?('a') }
          if types.size > 0
            types.each do |rdf_type|
              statements << RDF::Statement.new(object_bnode, RDF.type, uri_node(rdf_type['a']))
            end
          end

          subject = object_bnode
        end

        statements << RDF::Statement.new(
          subject,
          predicate_node(predicates.last.uri),
          statement[:statement].object
        )

        statements
      end

      def bnode_by_bnode_key(bnode_key)
        unless @bnode.key?(bnode_key)
          @bnode[bnode_key] = RDF::Node.new
        end

        @bnode[bnode_key]
      end

      def reject_prefix_lines(turtle)
        turtle.to_s.split("\n").reject { |line| line.start_with?('@prefix') }.join("\n")
      end

      def output_prefixes
        puts @prefixes.map { |prefix, uri| "@prefix #{prefix}: <#{uri}> ." }.join("\n")
      end

      def format_text
        ft = @convert.format.to_s.start_with?(':') ? @convert.format.to_s[1..-1] : @convert.format.to_s
        case ft
        when 'turtle'
          'Turtle'
        when 'ntriples'
          'N-Triples'
        else
          'unknown'
        end
      end

      def add_statement(statement)
        @statements << statement
      end
    end
  end
end

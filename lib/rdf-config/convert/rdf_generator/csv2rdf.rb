require 'benchmark'
require 'rdf/turtle'
require_relative '../rdf_generator'

class RDFConfig
  class Convert
    class CSV2RDF < RDFGenerator
      def initialize(config, convert)
        super

        @build_time = 0.0
        @write_time = 0.0
        @total_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def format_duration(total_seconds)
        total_seconds = total_seconds.to_i

        hours = total_seconds / 3600
        minutes = (total_seconds % 3600) / 60
        seconds = total_seconds % 60

        "#{hours}時間#{minutes}分#{seconds}秒"
      end

      def generate
        if turtle_format?
          output_prefixes
          puts
        end

        @convert.source_subject_map.each do |source, subject_names|
          @source = source
          @subject_names = subject_names

          @reader = @convert.file_reader(source: source)
          generate_statements
        end

        # refine_statements
        # output_rdf

        total_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @total_start
        read_and_batch_time = total_time - @build_time - @write_time

        warn "読込+バッチ化: #{format_duration(read_and_batch_time.round(3))}"
        warn "Triple生成   : #{format_duration(@build_time.round(3))}"
        warn "Turtle出力   : #{format_duration(@write_time.round(3))}"
        warn "全体         : #{format_duration(total_time.round(3))}"
      end

      private

      def generate_statements
        line_number = 1
        @reader.each_row(use_rust: true) do |row|
          t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @converter.push_target_row(row, clear_variable: true)
          generate_by_row(row)
          add_statements_for_row
          clear_bnode_cache
          @converter.pop_target_row
          t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @build_time += (t2 - t1)

          # if line_number % READ_DONE_LINES == 0
          #   warn "#{@reader.source}: #{line_number.delimited_string} lines have been read."
          # end

          if @convert.output_interval.positive? && (line_number % @convert.output_interval) == 0
            # warn "Generating #{format_text} data ..."
            # refine_statements
            t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            output_rdf
            t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            @write_time += (t2 - t1)
          end

          line_number += 1
        end

        # warn "#{@reader.source}: Finished reading the input data."
        # warn "Generating #{format_text} data ..."
        # refine_statements
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output_rdf
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @write_time += (t2 - t1)
      end

      def generate_by_triple(triple, values, value_idx)
        subject = @subject_node[triple.subject.name][value_idx]
        subject = @subject_node[triple.subject.name].first if subject.nil?

        if values[value_idx].is_a?(RDF::Graph)
          values[value_idx].statements.each do |statement|
            @one_row_statements << {
              statement: statement,
              triple: triple
            }
          end

          top_bnode = top_bnode_for(values[value_idx])
          @one_row_statements << {
            statement: RDF::Statement.new(subject, predicate_node(triple.predicate.uri), top_bnode),
            triple: triple
          }
        else
          # statement = RDF::Statement.new(
          #   subject,
          #   predicate_node(triple.predicate.uri),
          #   object_node_by_triple(triple, values[value_idx])
          # )
          @intermediate_statement = { type: 'triple', s_kind: 'iri', s: uri_node(subject) }
          @intermediate_statement.merge!(p: uri_node(triple.predicate.uri))
          @intermediate_statement.merge!(object_node_by_triple(triple, values[value_idx]))
          # @one_row_statements << {
          #   statement: statement,
          #   triple: triple
          # }
        end
      end

      def add_subject_relation(triple, subject_node, object_node)
        # statement = RDF::Statement.new(
        #   subject_node, predicate_node(triple.predicate.uri), object_node
        # )

        # @one_row_statements << {
        #   statement: statement,
        #   triple: triple
        # }
        @intermediate_statements << {
          type: 'triple',
          s_kind: 'iri',
          s: subject_node,
          p: uri_node(triple.predicate.uri),
          o_kind: 'iri',
          o: object_node
        }
      end

      def top_bnode_for(rdf_graph)
        subjects = rdf_graph.statements.map(&:subject).select { |subject| subject.is_a?(RDF::Node) }.uniq
        objects = rdf_graph.statements.map(&:object).select { |object| object.is_a?(RDF::Node) }.uniq

        (subjects - objects).first
      end
    end
  end
end

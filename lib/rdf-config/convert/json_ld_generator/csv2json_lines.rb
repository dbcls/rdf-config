# frozen_string_literal: true

require_relative 'csv2json_ld'

class RDFConfig
  class Convert
    class CSV2JSON_Lines < CSV2JSON_LD
      DEFAULT_CONTEXT_FILE_NAME = 'context.jsonld'

      def initialize(config, convert)
        super

        @context_generator = ContextGenerator.new(@config)
        @jsonld_context = nil
      end

      def generate(per_line: true)
        process_all_sources(per_line: per_line)
        if per_line
          generate_context unless @convert.output_path.nil?
          return
        end

        refine_nodes
        output_jsonl_lines(per_line: false)
        File.open(DEFAULT_CONTEXT_FILE_NAME, 'w') do |f|
          f.puts JSON.generate({ '@context' => @jsonld_context })
        end
      end

      def generate_context
        if @convert.output_path
          File.open(context_file_path, 'w') { |f| f.puts JSON.generate(@context_generator.generate_by_convert_config) }
        else
          puts JSON.generate(@context_generator.generate_by_convert_config)
        end
        # process_all_sources(per_line: false)
        # process_node
        # puts JSON.generate({ '@context' => @jsonld_context })
      end

      private

      def output_jsonl_lines(per_line: true)
        process_node do |data_hash|
          jsonl_line = JSON.generate({ '@context' => context_url }.merge(data_hash))

          if per_line && @check_jsonl_duplicate
            unless @outputted_jsonl_lines.include?(jsonl_line)
              puts jsonl_line
              @outputted_jsonl_lines << jsonl_line
            end
          else
            puts jsonl_line
          end
        end
      end

      def process_source(source, subject_names, per_line: false)
        @converter.clear_target_rows
        @reader = @convert.file_reader(source: source)
        @subject_names = subject_names
        generate_graph(per_line: per_line)
      end

      def process_node
        @jsonld_context = @config.prefix.transform_values { |uri| uri[1..-2] }
        final_nodes.each do |data_hash|
          subject_name = data_hash.keys.select { |key| @model.subject?(key) }.first
          @jsonld_context =
            @jsonld_context.merge(@context_generator.context_for_data_hash(subject_name, data_hash))

          yield data_hash if block_given?
        end
      end

      def context_file_path
        if File.directory?(@convert.output_path)
          File.join(@convert.output_path, DEFAULT_CONTEXT_FILE_NAME)
        else
          @convert.output_path
        end
      end

      def context_url
        if @convert.output_path
          File.absolute_path(context_file_path)
        else
          DEFAULT_CONTEXT_FILE_NAME
        end
      end
    end
  end
end

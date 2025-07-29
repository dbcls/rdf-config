# frozen_string_literal: true

require 'json'
require_relative '../generator'
require_relative '../mix_in/convert_util'
require_relative 'context_generator'
require_relative 'nest_generator'

class RDFConfig
  class Convert
    class CSV2JSON_LD < Generator
      include MixIn::ConvertUtil

      TYPE_KEY = '@type'

      def initialize(config, convert)
        super

        @context = ContextGenerator.new(config).prefix_key_value_pairs

        @node_per_line = {}
        @node = {}
        @type_in_context = false

        @check_jsonl_duplicate = false
        @outputted_jsonl_lines = []
        @check_node_duplicate = true
        @print_perline_progress = true

        @nest_node = false
        @object_triple_map = {}
      end

      def generate(per_line: false)
        process_all_sources(per_line: per_line)
        refine_nodes unless per_line

        json_ld = {
          '@context' => @context,
          data: final_nodes
        }

        puts JSON.generate(json_ld)
      end

      private

      def generate_context
        @subject_node.each_key do |subject_name|
          @context[subject_name] = '@id'
          @context[subject_type_key(subject_name)] = TYPE_KEY if @type_in_context
        end

        @context['data'] = '@graph'

        @object_triple_map.each do |object_name, triple|
          next if triple.nil?

          hash = { '@id' => triple.predicates.last.uri }
          object = triple.object.first_instance
          case object
          when Model::URI, Model::Subject
            hash[TYPE_KEY] = '@id'
          when Model::Literal
            datatype = extract_rdf_datatype(object.value)
            hash[TYPE_KEY] = datatype unless datatype.nil?
          end
          @context[object_name] = hash
        end
      end

      def generate_graph(per_line: true)
        if @print_perline_progress
          line_number = 1
          start_time = Time.now
        end

        @reader.each_row do |row|
          clear_bnode_cache
          @converter.push_target_row(row, clear_variable: true)
          generate_by_row(row)
          if per_line
            @node = @node_per_line
            refine_nodes
            @node.each do |subject_uri, node_hash|
              @node[subject_uri] = modeling_node(node_hash)
            end
            output_jsonl_lines
            @node = {}
            @node_per_line = {}
          else
            @node_per_line.each do |subject_uri, node_hash|
              modeling_node(node_hash).each do |variable_name, node_value|
                add_node(@node, subject_uri, { variable_name => node_value })
              end
            end
            @node_per_line = {}
          end
          @converter.pop_target_row
          next unless @print_perline_progress

          end_time = Time.now
          warn "#{sprintf('%7d', line_number)}: #{sprintf('%.4f', end_time - start_time)}s"
          start_time = end_time
          line_number += 1
        end
      end

      def process_all_sources(per_line: false)
        @convert.source_subject_map.each do |source, subject_names|
          process_source(source, subject_names, per_line: per_line)
        end
      end

      def process_source(source, subject_names, per_line: false)
        @converter.clear_target_rows
        @reader = @convert.file_reader(source: source)

        @source = source
        @subject_names = subject_names
        generate_graph(per_line: per_line)
        generate_context unless per_line
      end

      def generate_subject(subject_name, subject_value)
        subject_uri = subject_value.dup
        add_subject_node(subject_name, subject_uri)
        add_node(@node_per_line, subject_uri, { subject_name => subject_uri })
        add_subject_type_node(subject_name, subject_uri) unless @convert.has_rdf_type_object?
      end

      def generate_bnode_subject(subject_name)
        generate_bnode_id
        generate_subject(subject_name, bnode_uri)
      end

      def generate_by_triple(triple, values, value_idx)
        subject_name = triple.subject.name

        subject_iri = @subject_node[subject_name][value_idx]
        subject_iri = @subject_node[subject_name].first if subject_iri.nil?

        add_node(@node_per_line,
                 subject_iri,
                 object_hash_by_triple(triple, cast_data_type(values[value_idx], triple.object)))
      end

      def object_hash_by_triple(triple, values)
        { triple.object_name => values }
      end

      def add_subject_relation(triple, subject_node, object_node)
        @object_triple_map[triple.object_name] = triple unless @object_triple_map.key?(triple.object_name)
        add_node(@node_per_line, subject_node, { triple.object_name => object_node })
      end

      def type_value_by_subject(subject)
        if subject.types.nil? || subject.types.empty?
          nil
        elsif subject.types.size == 1
          subject.types.first
        else
          subject.types
        end
      end

      def add_node(node, subject_uri, node_hash)
        object_key = node_hash.keys.first
        return if @check_node_duplicate && node.key?(subject_uri) && node[subject_uri][object_key] == node_hash[object_key]

        node_value = add_language(node_hash[object_key])
        if node.key?(subject_uri)
          if node[subject_uri].key?(object_key)
            node[subject_uri][object_key] = [node[subject_uri][object_key]] unless node[subject_uri][object_key].is_a?(Array)
            node[subject_uri][object_key] << node_value
          else
            node[subject_uri][object_key] = node_value
          end
        else
          node[subject_uri] = { object_key => node_value }
        end
      end

      def add_language(node_value)
        if node_value.is_a?(RDF::Literal) && !node_value.language.to_s.empty?
          {
            '@value' => node_value.to_s,
            '@language' => node_value.language
          }
        else
          node_value
        end
      end

      def add_subject_type_node(subject_name, subject_uri)
        subject = @model.find_subject(subject_name)
        return if subject.nil?

        json_object_type = type_value_by_subject(subject)
        return if json_object_type.nil?

        add_node(@node_per_line, subject_uri, { subject_type_key(subject_name) => json_object_type })
      end

      def bnode_uri?(uri)
        uri =~ /\A_:.*/
      end

      def cast_data_type(target_value, triple_object)
        return nil if target_value.nil?

        object = triple_object.first_instance

        return target_value if !target_value.is_a?(String) || !object.is_a?(Model::Literal)

        case object.value
        when Integer
          target_value.to_s.to_i
        when Float
          target_value.to_s.to_f
        else
          target_value
        end
      end

      def subject_type_key(subject_name)
        if @type_in_context
          "#{subject_name}_type"
        else
          TYPE_KEY
        end
      end

      def refine_nodes
        remove_subject_uris = rdftype_only_subject_uris
        until remove_subject_uris.empty?
          remove_rdftype_only_subjects(remove_subject_uris)
          remove_no_connection_nodes

          remove_subject_uris = rdftype_only_subject_uris
        end
      end

      def rdftype_only_subject_uris
        @node.keys.select { |subject_uri| rdftype_only?(subject_uri) }
      end

      def rdftype_only?(subject_uri)
        return false unless @node.key?(subject_uri)

        node_hash = @node[subject_uri]
        node_hash.size <= if node_hash.key?(TYPE_KEY)
                            2
                          else
                            1
                          end
      end

      def remove_rdftype_only_subjects(remove_subject_uris)
        @node.reject! { |subject_uri, node_hash| remove_subject_uris.include?(subject_uri) }
      end

      def remove_no_connection_nodes
        @node.each do |subject_uri, node_hash|
          @node[subject_uri] = no_connection_removed_node(node_hash)
        end
      end

      def no_connection_removed_node(node_hash)
        valid_subject_uris = @node.keys
        node_array = node_hash.map do |variable_name, value|
          if variable_name == TYPE_KEY || @model.subject?(variable_name)
            [variable_name, value]
          else
            triple = @model.find_by_object_name(variable_name)
            if triple.nil?
              [variable_name, value]
            else
              object = triple.object.is_a?(Model::ValueList) ? triple.object.first_instance : triple.object
              if object.is_a?(Model::Subject)
                node_value = refined_node_value(value, valid_subject_uris)
                [variable_name, node_value] unless node_value.nil?
              else
                [variable_name, value]
              end
            end
          end
        end

        node_array.reject(&:nil?).to_h
      end

      def refined_node_value(value, valid_subject_uris)
        valid_values = []
        if value.is_a?(Array)
          valid_values = value.select { |v| valid_subject_uris.include?(v) }
        elsif valid_subject_uris.include?(value)
          valid_values << value
        end

        if valid_values.size == 1
          valid_values.first
        elsif valid_values.size > 1
          valid_values
        end
      end

      def final_nodes
        if @nest_node
          nest_generator = JsonLdGenerator::NestGenerator.new(@model, @node)
          nest_generator.generate
        else
          @node.values
        end
      end

      def modeling_node(node, subject_uri: nil)
        new_node = {}
        subject_uri = node.select { |variable_name, _| variable_name =~ /\A[A-Z]/ }.values.first if subject_uri.nil?
        node.each do |variable_name, value|
          if variable_name =~ /\A[a-z]/
            triple = triple_by_object_name(variable_name)
            predicates = triple.predicates
            if predicates.size == 1
              new_node[variable_name] = value
            else
              generate_blank_node(subject_uri, triple)
              bnode = blank_node(subject_uri, triple.predicates[0..-2].map(&:uri).join('/'))
              bnode[variable_name] = value
            end
          else
            new_node[variable_name] = value
          end
        end

        top_bnode = @bnode.select do |key, _|
          key.start_with?(subject_uri) && key.split(';').last.split('/').size == 1
        end
        if top_bnode
          top_bnode.each do |key, value|
            new_node[key.split(';').last] = value
          end
        end

        new_node
      end

      def triple_by_object_name(object_name)
        @object_triple_map[object_name] ||= @model.find_by_object_name(object_name)
      end

      def generate_blank_node(subject_uri, triple)
        prev_bnode = nil
        predicates = triple.predicates
        paths =
          (1...predicates.length).map { |i| predicates[0...i].map(&:uri).join('/') }
        paths.each do |path|
          num_paths = path.split('/').size
          key = bnode_key(subject_uri, path)
          unless @bnode.key?(key)
            @bnode[key] = {}
            types = predicates[num_paths-1].objects.first.values.first.select { |h| h.key?('a') }
            if types.size == 1
              @bnode[key]['@type'] = types.first['a']
            elsif types.size > 1
              @bnode[key]['@type'] = types.map { |h| h['a'] }
            end
          end

          if prev_bnode
            prev_bnode[predicates[num_paths-1].uri] = @bnode[key]
          end

          prev_bnode = @bnode[key]
        end
      end

      def blank_node(subject_uri, property_path)
        @bnode[bnode_key(subject_uri, property_path)]
      end

      def bnode_key(subject_uri, property_path)
        [subject_uri, property_path].join(';')
      end
    end
  end
end

# frozen_string_literal: true

require 'json'
require_relative '../generator'
require_relative '../mix_in/convert_util'
require_relative 'context_generator'

class RDFConfig
  class Convert
    class CSV2JSON_LD < Generator
      include MixIn::ConvertUtil

      TYPE_KEY = '@type'

      def initialize(config, convert)
        super

        @json_ld = {
          '@context' => {}
        }
        @context = {}
        @node = {}
        @type_in_context = false

        @context_generator = ContextGenerator.new(@config)
      end

      def generate
        @convert.source_subject_map.each do |source, subject_names|
          @converter.clear_target_rows
          @reader = @convert.file_reader(source: source)
          @subject_names = subject_names
          generate_graph
          generate_context
        end

        refine_nodes

        # json_data = @node.map { |id, hash| { '@id' => id }.merge(hash) }
        @json_ld.merge!(data: @node.values)

        # puts JSON.pretty_generate(@json_ld)
        puts JSON.generate(@json_ld)
      end

      def generate_json_lines
        @convert.source_subject_map.each do |source, subject_names|
          @converter.clear_target_rows
          @reader = @convert.file_reader(source: source)
          @subject_names = subject_names
          generate_graph
        end

        refine_nodes

        json_ld_ctx = @config.prefix.transform_values { |uri| uri[1..-2] }
        @node.each_value do |data_hash|
          subject_name = data_hash.keys.select { |key| @model.subject?(key) }.first
          json_ld_ctx =
            json_ld_ctx.merge(@context_generator.context_for_data_hash(subject_name, data_hash))
          puts JSON.generate({ '@context' => context_url }.merge(data_hash))
        end

        File.open(context_file, 'w') do |f|
          f.puts JSON.generate({ '@context' => json_ld_ctx })
        end
      end

      private

      def generate_context
        add_prefixes_to_context

        @subject_node.each_key do |subject_name|
          @json_ld['@context'][subject_name] = '@id'
          @json_ld['@context'][subject_type_key(subject_name)] = TYPE_KEY if @type_in_context
        end

        @json_ld['@context']['data'] = '@graph'

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
          @json_ld['@context'][object_name] = hash
        end
      end

      def generate_graph
        @reader.each_row do |row|
          @converter.push_target_row(row, clear_variable: true)
          generate_by_row(row)
          @converter.pop_target_row
        end
      end

      def generate_subject(subject_name, subject_value)
        subject_uri = subject_value.dup
        add_subject_node(subject_name, subject_uri)
        add_node(subject_uri, { subject_name => subject_uri })
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

        add_node(subject_iri,
                 object_hash_by_triple(triple, cast_data_type(values[value_idx], triple.object)))
      end

      def object_hash_by_triple(triple, values)
        { triple.object.name => values }
      end

      def add_subject_relation(triple, subject_node, object_node)
        @object_triple_map[triple.object_name] = triple unless @object_triple_map.key?(triple.object_name)
        add_node(subject_node, { triple.object_name => object_node })
      end

      def add_prefixes_to_context
        @config.prefix.each do |prefix, uri|
          @json_ld['@context'][prefix] = uri[1..-2]
        end
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

      def add_node(key, object_hash)
        object_key = object_hash.keys.first
        return if @node.key?(key) && @node[key][object_key] == object_hash[object_key]

        node_value = if object_hash[object_key].is_a?(RDF::Literal) && !object_hash[object_key].language.to_s.empty?
                       {
                         '@value' => object_hash[object_key].to_s,
                         '@language' => object_hash[object_key].language
                       }
                     else
                       object_hash[object_key]
                     end

        if @node.key?(key)
          if @node[key].key?(object_key)
            @node[key][object_key] = [@node[key][object_key]] unless @node[key][object_key].is_a?(Array)
            @node[key][object_key] << node_value
          else
            @node[key][object_key] = node_value
          end
        else
          @node[key] = { object_key => node_value }
        end
      end

      def add_subject_type_node(subject_name, subject_uri)
        subject = @model.find_subject(subject_name)
        return if subject.nil?

        json_object_type = type_value_by_subject(subject)
        return if json_object_type.nil?

        add_node(subject_uri, { subject_type_key(subject_name) => json_object_type })
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

      def context_file
        'context.jsonld'
      end

      def context_url
        context_file
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
    end
  end
end

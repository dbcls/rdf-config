# frozen_string_literal: true

require 'json'
require_relative '../generator'
require_relative '../mix_in/convert_util'
require_relative 'context_generator'

class RDFConfig
  class Convert
    class CSV2JSON_LD < Generator
      include MixIn::ConvertUtil

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

        @node.values.each do |data_hash|
          subject_name = data_hash.keys.select { |key| @model.subject?(key) }.first
          jsonld_ctx =
            @context_generator.context_for_data_hash(subject_name, data_hash)
          puts JSON.generate({'@context' => jsonld_ctx }.merge(data_hash))
        end
      end

      private

      def generate_context
        add_prefixes_to_context

        @subject_node.each_key do |subject_name|
          @json_ld['@context'][subject_name] = '@id'
          @json_ld['@context'][subject_type_key(subject_name)] = '@type' if @type_in_context
        end

        @json_ld['@context']['data'] = '@graph'

        @object_triple_map.each do |object_name, triple|
          next if triple.nil?

          hash = { '@id' => triple.predicates.last.uri }
          object = triple.object.is_a?(Model::ValueList) ? triple.object.value.first : triple.object
          case object
          when Model::URI, Model::Subject
            hash['@type'] = '@id'
          when Model::Literal
            datatype = extract_rdf_datatype(object.value)
            hash['@type'] = datatype unless datatype.nil?
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
        subject_key = subject_value.dup
        add_subject_node(subject_name, subject_key)
        add_node(subject_key, { subject_name => subject_value })
      end

      def generate_by_triple(triple, values, value_idx)
        subject_name = triple.subject.name

        subject_iri = @subject_node[subject_name][value_idx]
        subject_iri = @subject_node[subject_name].first if subject_iri.nil?

        json_object_type = type_value_by_subject(triple.subject)
        add_node(subject_iri, { subject_type_key(subject_name) => json_object_type }) unless json_object_type.nil?

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

      def add_node_t(key, object_hash); end

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

      def cast_data_type(target_value, triple_object)
        return nil if target_value.nil?

        object = if triple_object.is_a?(Model::ValueList)
                   triple_object.value.first
                 else
                   triple_object
                 end

        return target_value unless object.is_a?(Model::Literal)

        case object.value
        when 'Integer'
          target_value.to_s.to_i
        when 'Float'
          target_value.to_s.to_f
        else
          target_value
        end
      end

      def subject_type_key(subject_name)
        if @type_in_context
          "#{subject_name}_type"
        else
          '@type'
        end
      end
    end
  end
end

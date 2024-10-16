# frozen_string_literal: true

require_relative '../mix_in/convert_util'

class RDFConfig
  class Convert
    class ContextGenerator
      include MixIn::ConvertUtil

      def initialize(config, **opts)
        @config = config
        @opts = opts

        @model = Model.instance(@config)
        @prefix_hash = prefix_hash_by_config(config)

        # key is subject name
        @context_map = generate_context_map
        @prefixes_map = prefixes_map_by_context_map
      end

      def context_for_data_hash(subject_name, data_hash)
        context_key_hash = extract_context_key_by_data_hash(subject_name, data_hash)

        prefixes =
          context_key_hash[:prefixes].select { |prefix| @prefix_hash.key?(prefix) } + @prefixes_map[subject_name]
        prefixes = prefixes.flatten.uniq
        variable_names = context_key_hash[:variable_names].unshift(subject_name)

        prefix_context = @prefix_hash.select { |prefix, uri|  prefixes.include?(prefix) }
        variable_context = variable_names.map { |variable| [variable, @context_map[subject_name][variable]] }.to_h

        prefix_context.merge(variable_context)
      end

      private

      def generate_context_map
        subject_contexts = {}
        @model.subject_names.each do |subject_name|
          subject_contexts[subject_name] = generate_context_by_subject_name(subject_name)
        end

        subject_contexts
      end

      def generate_context_by_subject_name(subject_name)
        jsonld_context =  { subject_name => '@id' }
        @model.triples_by_subject_name(subject_name).each do |triple|
          hash = { '@id' => triple.predicates.last.uri }
          object = triple.object.first_instance
          case object
          when Model::URI, Model::Subject
            hash['@type'] = '@id'
          when Model::Literal
            datatype = extract_rdf_datatype(object.value)
            hash['@type'] = datatype unless datatype.nil?
          end
          jsonld_context[triple.object_name] = hash
        end

        jsonld_context
      end

      def extract_context_key_by_data_hash(subject_name, data_hash)
        prefixes = []
        variable_names = []
        data_hash.each do |variable_name, data_hash_value|
          variable_names << variable_name if variable_name != subject_name && @context_map[subject_name].key?(variable_name)

          values = if data_hash_value.is_a?(Array)
                     data_hash_value
                   else
                     [data_hash_value]
                   end

          prefixes += values.select.map { |value| prefix_by_uri(value) }.reject(&:nil?)
        end

        { prefixes: prefixes.flatten.uniq, variable_names: variable_names }
      end

      def prefixes_map_by_context_map
        prefixes_map = {}
        @context_map.each do |subject_name, context_value|
          prefixes_map[subject_name] = prefixes_by_context_value(context_value)
        end

        prefixes_map
      end

      def prefixes_by_context_value(context_value)
        prefixes = []
        context_value.values.select { |value| value.is_a?(Hash) }.each do |value_hash|
          if value_hash.key?('@id') && value_hash['@id'].is_a?(String)
            prefixes << prefix_by_uri(value_hash['@id'])
          end

          if value_hash.key?('@type') && value_hash['@type'] != '@id'
            prefixes << prefix_by_uri(value_hash['@type'])
          end
        end

        prefixes.uniq
      end

      def prefix_hash_by_config(config)
        config.prefix.map { |prefix, uri| [prefix, uri[1..-2]] }.to_h
      end
    end
  end
end

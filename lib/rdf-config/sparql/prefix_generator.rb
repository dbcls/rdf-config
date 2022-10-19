require 'rdf-config/sparql'

class RDFConfig
  class SPARQL
    class PrefixGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = []
        @configs.each do |config|
          init_instance_variables
          @config = config
          lines += generate_by_config
        end
        lines << ''

        lines.uniq
      end

      def generate_by_config
        lines = []
        used_prefixes.each do |prefix|
          lines << "PREFIX #{prefix}: #{namespace[prefix]}"
        end

        lines
      end

      private

      def used_prefixes
        (used_prefixes_by_variable + used_prefixes_by_parameter).uniq
      end

      def used_prefixes_by_variable
        prefixes = []

        variables.each do |variable_name|
          triples = model.triples_by_object_name(variable_name)
          # triples = model.triples_by_subject_name(variable_name) if triples.empty?

          triples.each do |triple|
            uris = triple.subject.types.flatten +
                   triple.predicates.map(&:uri).flatten +
                   model.bnode_rdf_types(triple).flatten
            case triple.object
            when Model::Subject
              uris += triple.object.types.flatten
            when Model::ValueList
              triple.object.value.each do |v|
                uris += v.types.flatten if v.is_a?(Model::Subject)
              end
            end

            uris.each do |uri|
              if /\A(\w+):\w+\z/ =~ uri
                prefix = Regexp.last_match(1)
                prefixes << prefix unless prefixes.include?(prefix)
              end
            end
          end
        end

        prefixes
      end

      def used_prefixes_by_parameter
        prefixes = []

        parameters.each do |var_name, value|
          object = model.find_object(var_name)
          next if !object.is_a?(Model::URI) && !object.is_a?(Model::Subject) && !model.subject?(var_name)

          prefixes << Regexp.last_match(1) if /\A(\w+):(.+)/ =~ value && !prefixes.include?(Regexp.last_match(1))
        end

        prefixes
      end
    end
  end
end

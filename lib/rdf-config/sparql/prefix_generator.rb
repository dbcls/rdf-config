require 'rdf-config/sparql'

class RDFConfig
  class SPARQL
    class PrefixGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        lines = []

        used_prefixes.uniq.each do |prefix|
          lines << "PREFIX #{prefix}: #{namespace[prefix]}"
        end
        lines << ''

        lines
      end

      private

      def used_prefixes
        prefixes = used_prefixes_by_variable
        prefixes += used_prefixes_by_parameter

        prefixes
      end

      def used_prefixes_by_variable
        prefixes = []

        variables.each do |variable_name|
          triples = model.triples_by_object_name(variable_name)
          next if triples.nil?

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
          next if !object.is_a?(Model::URI) && !object.is_a?(Model::Subject)

          if /\A(\w+):(.+)/ =~ value && !prefixes.include?($1)
            prefixes << $1
          end
        end

        prefixes
      end

    end
  end
end

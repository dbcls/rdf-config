require_relative '../endpoint'

class RDFConfig
  class Grasp
    module CommonMethods
      IRI_ARG_NAME = 'iri'.freeze
      ID_ARG_NAME = 'id'.freeze

      def triples
        @model.triples_by_subject_name(@subject.name).reject do |triple|
          triple.predicate.rdf_type? && triple.object_name.to_s.strip.empty?
        end
      end

      def object_names
        triples.map(&:object_name).reject { |name| name.to_s.strip.empty? }
      end

      def endpoint_url
        endpoint = Endpoint.new(@config)

        endpoint.primary_endpoint
      end
    end
  end
end

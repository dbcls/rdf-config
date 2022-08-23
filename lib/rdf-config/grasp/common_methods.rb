class RDFConfig
  class Grasp
    module CommonMethods
      IRI_ARG_NAME = 'iri'.freeze

      def triples
        @model.triples_by_subject_name(@subject.name).reject { |triple| triple.predicate.rdf_type? }
      end

      def object_names
        triples.map(&:object_name).reject { |name| name.to_s.strip.empty? }
      end

      # TODO: config -> config_name, subject -> subject_nameにする？
      def subject_type_name(config, subject)
        "#{to_camel_case(config.name)}#{subject.name}"
      end

      # TODO: config -> config_name, object -> object_nameにする？
      def union_type_name(config, object)
        "#{to_camel_case(config.name)}#{object.name.capitalize}"
      end

      def to_camel_case(s)
        s.split(/[_-]/).map(&:capitalize).join
      end
    end
  end
end

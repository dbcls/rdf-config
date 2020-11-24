class RDFConfig
  class Grasp
    module DataType
      def data_type_lines(triples)
        subjects = []

        lines = []
        triples.each do |triple|
          next if triple.predicate.rdf_type?

          subject = triple.subject
          unless subjects.include?(subject.name)
            lines << "#{INDENT}#{subject.name}: String!" unless subject.used_as_object?
            subjects << subject.name
          end
          lines << "#{INDENT}#{triple.object_name}: #{data_type_desc(triple)}"
        end

        lines
      end

      def data_type_by_rdf_object(object)
        case object
        when Model::Subject
          # Object type
          object.name
        else
          # Scalar type
          case object.type
          when 'URI'
            'String'
          when 'Int', 'Float'
            object.type
          when 'TrueClass', 'FalseClass'
            'Boolean'
          else
            'String'
          end
        end
      end

      def dataset_subject(model)
        subject = model.subjects.reject(&:used_as_object?).first
        if subject.nil?
          subject = model.subjects.first
        end

        subject
      end

      def data_type_desc(triple)
        desc = data_type_by_rdf_object(triple.object)
        desc = "[#{desc}]" if triple.predicate.plural?
        desc = "#{desc}!" if triple.predicate.required?

        desc
      end
    end
  end
end

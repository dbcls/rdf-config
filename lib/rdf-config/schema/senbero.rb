class RDFConfig
  class Schema
    class Senbero
      def initialize(config)
        @model = Model.instance(config)
      end

      def color_subject(str)
        "\033[35m#{str}\033[0m"
      end

      def color_predicate(str)
        "\033[33m#{str}\033[0m"
      end

      def color_object(str)
        "\033[36m#{str}\033[0m"
      end

      def color_property_path(predicates, separator = ' / ')
        predicates.map { |x|
          predicate = color_predicate(x.uri)
          cardinality = x.cardinality ? " #{x.cardinality.label}" : ''
          "#{predicate}#{cardinality}"
        }.join(separator)
      end

      def label_object(object)
        case object
        when Model::URI
          object.value
        when Model::Literal
          object.value.inspect
        when Model::Subject
          color_subject(object.name)
        when Model::ValueList
          "[#{object.value.map { |obj| label_object(obj) }.join(', ')}]"
        else
          label = object.value.to_s
          if label.empty?
            'N/A'
          else
            label
          end
        end
      end

      def generate
        seen = {}
        rdf_type = ''
        @model.each do |triple|
          if triple.predicate.rdf_type?
            rdf_type = triple.predicate.objects.map(&:name).join(',')
            next
          end

          subject = triple.subject
          unless seen.keys.include?(subject.name)
            seen[subject.name] = {}

            # output subject
            subject_class = subject.type
            subject_color = color_subject(subject.name)
            subject_str   = subject_color
            subject_str  += " [#{subject_class}]" unless subject_class.empty?
            subject_str  += subject.name == [] ? ' (blank_node)' : " (#{subject.value})"
            puts subject_str
          end

          unless seen[subject.name].key?("#{rdf_type}:#{triple.property_path}")
            # output predicate
            predicate_color = color_property_path(triple.predicates)
            if triple.last_predicate?(@model)
              puts "    `-- #{predicate_color}"
            else
              puts "    |-- #{predicate_color}"
            end

            seen[subject.name]["#{rdf_type}:#{triple.property_path}"] = true
          end

          # output object
          object_color = color_object(triple.object_name)
          object_label = label_object(triple.object)

          if triple.last_predicate?(@model)
            if triple.last_object?(@model)
              puts "            `-- #{object_color} (#{object_label})"
            else
              puts "            |-- #{object_color} (#{object_label})"
            end
          else
            if triple.last_object?(@model)
              puts "    |       `-- #{object_color} (#{object_label})"
            else
              puts "    |       |-- #{object_color} (#{object_label})"
            end
          end
        end

        @model.print_warnings
      end
    end
  end
end

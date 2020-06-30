class RDFConfig
  class Schema
    class Senbero
      def initialize(config)
        @model = Model.new(config)
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
            puts "#{subject_color} (#{subject_class})"
          end

          unless seen[subject.name].key?("#{rdf_type}:#{triple.property_path}")
            # output predicate
            predicate_color = color_predicate(triple.property_path)
            if triple.last_predicate?(@model)
              puts "    `-- #{predicate_color}"
            else
              puts "    |-- #{predicate_color}"
            end

            seen[subject.name]["#{rdf_type}:#{triple.property_path}"] = true
          end

          # output object
          object_color = color_object(triple.object_name)
          object_label = case triple.object
                         when Model::URI
                           triple.object_value
                         when Model::Literal
                           triple.object_value.inspect
                         when Model::Subject
                           color_subject(triple.object_value)
                         else
                           'N/A'
                         end

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
      end
    end
  end
end

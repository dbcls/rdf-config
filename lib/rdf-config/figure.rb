class RDFConfig

  class Figure
    def initialize(model)
      @model = model
    end

    class Senbero < Figure
      def initialize(model)
        super
      end

      def generate
        @model.subjects.each do |subject|
          subject_class = @model.subject_type_map[subject]
          puts "#{subject} (#{subject_class})"
          predicates = @model.predicates[subject]
          predicates.each_with_index do |predicate, i|
            if i < predicates.size - 1
              puts "    |-- #{predicate}"
            else
              puts "    `-- #{predicate}"
            end
            objects = @model.objects[subject][predicate]
            objects.each_with_index do |object, j|
              object_label = @model.object_label_map[subject][object].inspect
              if i < predicates.size - 1
                if j < objects.size - 1
                  puts "    |       |-- #{object} (#{object_label})"
                else
                  puts "    |       `-- #{object} (#{object_label})"
                end
              else
                if j < objects.size - 1
                  puts "            |-- #{object} (#{object_label})"
                else
                  puts "            `-- #{object} (#{object_label})"
                end
              end
            end
          end
        end
      end
    end

    class Schema < Figure
    end
  end

end

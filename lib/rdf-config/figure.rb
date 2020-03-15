class RDFConfig

  class Figure
    def initialize(config_dir)
      @model = Model.new(config_dir)
    end

    class Senbero < Figure
      def initialize(config_dir)
        super
      end

      def generate
        @model.subjects.each do |subject, hash|
          puts "#{subject} (#{subject_label(hash)})"
          predicates(hash).each do |predicate, hash|
            puts "    |-- #{predicate}"
            object = hash["object"]
            puts "    |       `-- #{object['type']} (#{object['example']})"
          end
        end
      end
    end

    class Schema < Figure
    end
  end

end

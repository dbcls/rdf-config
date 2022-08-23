class RDFConfig
  class Model
    Cardinality = Struct.new(:label, :min, :max)

    class Triple
      attr_reader :subject, :predicates, :object

      def initialize(subject, predicates, object)
        @subject = subject
        @predicates = predicates
        @object = object
      end

      def predicate
        @predicates.last
      end

      def property_path(separator = ' / ')
        @predicates.map(&:uri).join(separator)
      end

      def last_predicate?(model)
        last_property_path = model.select { |triple| triple.subject.name == subject.name }.last.property_path

        property_path == last_property_path
      end

      def last_object?(model)
        idx = model.find_index(self)

        model.size == idx + 1 || model[idx].property_path != model[idx + 1].property_path
      end

      def subject_name
        @subject.name
      end

      def object_name
        case @object
        when Model::Subject
          @object.as_object_name
        else
          @object.name
        end
      end

      def object_value
        case @object
        when Model::Subject
          @object.as_object_value
        else
          @object.value
        end
      end

      def bnode_connecting?
        @predicates.size > 1
      end

      def ==(other)
        subject.name == other.subject.name &&
          property_path == other.property_path &&
          object_name == other.object_name
      end

      def to_s
        "#{subject.name} #{property_path} #{object_name}"
      end
    end
  end
end

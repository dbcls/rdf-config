class RDFConfig
  class Model
    class Subject
      attr_reader :name, :value, :as_object
      attr_accessor :bnode_name

      def initialize(subject_hash, prefix_hash = {})
        @prefix_hash = prefix_hash
        @as_object = {}

        key = subject_hash.keys.first
        if key.is_a?(Array)
          @name = key
          @value = nil
        else
          @name, @value = key.split(/\s+/, 2)
        end

        @predicates = []
      end

      def predicates(reject_rdf_type_variable: false)
        if reject_rdf_type_variable
          @predicates.reject do |predicate|
            predicate.rdf_type? &&
              predicate.objects
                       .map(&:name).map(&:to_s).map(&:strip)
                       .select { |object_name| object_name.length > 0 }.size > 0
          end
        else
          @predicates
        end
      end

      def types
        predicates(reject_rdf_type_variable: true).select(&:rdf_type?).map do |predicate|
          case predicate.objects.first
          when ValueList
            predicate.objects.first.value.map(&:value)
          else
            predicate.objects.map(&:value)
          end
        end.flatten
      end

      def type(separator = ', ')
        types.uniq.join(separator)
      end

      def has_rdf_type?
        !types.empty?
      end

      def blank_node?
        @name.is_a?(Array) || @value.to_s == '[]'
      end

      def objects(opts = {})
        predicates = if opts[:reject_rdf_type]
                       @predicates.reject(&:rdf_type?)
                     else
                       @predicates
                     end

        predicates.map(&:objects).flatten
      end

      def object_names
        @predicates.reject(&:rdf_type?).map(&:objects).flatten.map do |object|
          if object.is_a?(Subject)
            object.as_object_name
          else
            object.name
          end
        end
      end

      def add_predicates(predicate_object_hashes)
        predicate_object_hashes.each do |predicate_object_hash|
          add_predicate(predicate_object_hash)
        end
      end

      def add_predicate(predicate)
        @predicates << predicate
      end

      def add_as_object(subject_name, predicate_uri, object)
        @as_object = {
          subject_name: subject_name,
          predicate_uri: predicate_uri,
          object: object
        }
      end

      def parent_subject_names
        if used_as_object?
          @as_object.keys
        else
          []
        end
      end

      def as_object_name
        @as_object[:object].name
      end

      def as_object_value
        @as_object[:object].value
      end

      def used_as_object?
        !@as_object.empty?
      end

      def instance_type
        'Subject'
      end

      def shex_data_type
        'IRI'
      end

      def ==(other)
        name == other.name
      end

      def subject?
        true
      end

      def uri?
        true
      end

      def literal?
        false
      end

      def value_list?
        false
      end

      def instances
        [self]
      end

      def first_instance
        self
      end

      def last_instance
        self
      end
    end
  end
end

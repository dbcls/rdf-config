class RDFConfig
  class Model
    class Subject
      attr_reader :name, :value, :predicates, :as_object
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

      def types
        rdf_type_predicates = @predicates.select(&:rdf_type?)
        rdf_type_predicates.map { |predicate| predicate.objects.map(&:value) }.flatten
      end

      def type(separator = ', ')
        types.join(separator)
      end

      def has_rdf_type?
        !types.empty?
      end

      def blank_node?
        @name.is_a?(Array)
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

      def ==(other)
        name == other.name
      end
    end
  end
end

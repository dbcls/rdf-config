require 'rdf-config/model/triple'
require 'rdf-config/model/validator'

class RDFConfig
  class Model
    include Enumerable

    def initialize(config)
      @config = config
      @graph = Graph.new(@config)
      @graph.generate
      generate_triples
      validate
    end

    def each
      @triples.each { |t| yield(t) }
    end

    def find_subject(subject_name)
      subjects.select { |subject| subject.name == subject_name }.first
    end

    def subject?(variable_name)
      !find_subject(variable_name).nil?
    end

    def find_by_predicates(predicates)
      @triples.select { |triple| triple.predicates == predicates }
    end

    def bnode_rdf_types(triple)
      rdf_types = []

      0.upto(triple.predicates.size - 2) do |i|
        rdf_type_triples = @triples.select do |t|
          t.predicates[0..i] == triple.predicates[0..i] &&
            t.predicates.size == i + 2 &&
            t.predicates.last.rdf_type?
        end

        if rdf_type_triples.empty?
          rdf_types << nil
        else
          types = []
          rdf_type_triples.each do |t|
            @bnode_subjects.select { |bn_subj| bn_subj.predicates.include?(t.predicate) }.each do |s|
              bn_obj = s.objects.select { |o| o.blank_node? }.first
              if bn_obj
                types << t.object_name
              else
                types << t.object_name if s.objects.include?(triple.object)
              end
            end
          end
          rdf_types << types
        end
      end

      rdf_types
    end

    def find_object(object_name)
      object = @triples.map(&:object).select { |object| object.name == object_name }.first
      if object.nil?
        object = find_subject(object_value[object_name])
      end

      object
    end

    def find_by_object_name(object_name)
      if subject?(object_name)
        @triples.select do |triple|
          case triple.object
          when Subject
            triple.object.name == object_name && triple.subject.name != object_name
          when ValueList
            subject_names = triple.object.value.select { |v| v.is_a?(Subject) }.map(&:name)
            if subject_names.include?(triple.subject.name)
              false
            else
              subject_names.include?(object_name)
            end
          else
            false
          end
        end.first
      else
        @triples.select { |triple| triple.object_name == object_name }.first
      end
    end

    def triples_by_object_name(object_name, start_subject = nil)
      triples = []

      triple = find_by_object_name(object_name)
      while triple
        triples << triple
        break if !start_subject.nil? && triple.subject.name == start_subject

        triple = find_by_object_name(triple.subject.name)
      end

      triples.reverse
    end

    def find_bnode_subject(object_name)
      @bnode_subjects.select { |s| s.objects.map(&:name) == object_name }.first
    end

    def object_names
      names = []

      @triples.each do |triple|
        next if triple.predicate.rdf_type?

        names << triple.object_name
      end

      names
    end

    def subjects
      @graph.subjects
    end

    def object_value
      @graph.object_value
    end

    def parent_subject_name(object_name)
      if subject?(object_name)
        subject = find_subject(object_name)
        if subject.used_as_object?
          subject.as_object.keys.include?(object_name) ? nil : subject.as_object.keys.first
        else
          nil
        end
      else
        triple = find_by_object_name(object_name)
        if triple.nil?
          nil
        else
          triple.subject.name
        end
      end
    end

    def parent_subject_names(object_name)
      triples_by_object_name(object_name).map(&:subject).map(&:name)
    end

    def parent_variable(object_name)
      triple = find_by_object_name(object_name)
      return nil if triple.nil? || !triple.subject.used_as_object?

      triple.subject.as_object.values.map(&:name).uniq.first
    end

    def parent_variables(object_name)
      variables = []
      loop do
        variable_name = parent_variable(object_name)
        break if variable_name.nil? || variable_name == object_name

        variables << variable_name
        object_name = variable_name
      end

      variables.reverse
    end

    def predicate_path(object_name, start_subject = nil)
      triples = triples_by_object_name(object_name, start_subject)
      return [] if triples.nil?

      triples.map(&:predicates).flatten
    end

    def property_path(object_name, start_subject = nil)
      predicate_path(object_name, start_subject).map(&:uri).flatten
    end

    def same_property_path_exist?(object_name)
      property_path_map.select { |obj_name, prop_path| prop_path == property_path(object_name) }.size > 1
    end

    def [](idx)
      @triples[idx]
    end

    def size
      @size ||= @triples.size
    end

    def validate
      validator = Validator.new(self, @config)
      validator.validate

      raise Config::InvalidConfig, validator.error_message if validator.error?
    end

    private

    def generate_triples
      @triples = []
      @predicates = []
      @bnode_subjects = []

      subjects.each do |subject|
        @subject = subject
        proc_subject(subject)
      end
    end

    def proc_subject(subject)
      subject.predicates.each do |predicate|
        @predicates.push(predicate)
        proc_predicate(predicate)
        @predicates.pop
      end
    end

    def proc_predicate(predicate)
      predicate.objects.each do |object|
        proc_object(object)
      end
    end

    def proc_object(object)
      if object.blank_node?
        @bnode_subjects << object.value
        proc_subject(object.value)
      else
        add_triple(Triple.new(@subject, Array.new(@predicates), object))
      end
    end

    def add_triple(triple)
      @triples << triple
    end

    def property_path_map
      return @property_path_map unless @property_path_map.nil?

      @property_path_map = {}
      object_names.each do |object_name|
        @property_path_map[object_name] = property_path(object_name)
      end

      @property_path_map
    end
  end
end

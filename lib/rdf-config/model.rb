require 'rdf-config/model/triple'
require 'rdf-config/model/validator'

class RDFConfig
  class Model
    include Enumerable

    attr_reader :subjects

    def initialize(config)
      @config = config
      @subjects = []

      generate_triples
      validate
    end

    def each
      @triples.each { |t| yield(t) }
    end

    def find_subject(subject_name)
      @subjects.select { |subject| subject.name == subject_name }.first
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
          rdf_type_triples.each do |t|
            @bnode_subjects.select { |bn_subj| bn_subj.predicates.include?(t.predicate) }.each do |s|
              bn_obj = s.objects.select { |o| o.blank_node? }.first
              if bn_obj
                rdf_types << s.types
              else
                rdf_types << s.types if s.objects.include?(triple.object)
              end
            end
          end
        end
      end

      rdf_types
    end

    def find_object(object_name)
      @triples.map(&:object).select { |object| object.name == object_name }.first
    end

    def find_by_object_name(object_name)
      if subject?(object_name)
        @triples.select { |triple| triple.object.name == object_name }.first
      else
        @triples.select { |triple| triple.object_name == object_name }.first
      end
    end

    def find_bnode_subject(object_name)
      @bnode_subjects.select { |s| s.objects.map(&:name) == object_name }.first
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

      @config.model.each do |subject_hash|
        @subjects << Model::Subject.new(subject_hash, @config.prefix)
      end

      @subjects.each do |subject|
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
      predicate.objects.each_with_index do |object, i|
        proc_object(predicate, object, i)
      end
    end

    def proc_object(predicate, object, idx)
      if object.blank_node?
        @bnode_subjects << object.value
        proc_subject(object.value)
      else
        subject_as_object = find_subject(object.value)
        if subject_as_object.nil?
          add_triple(Triple.new(@subject, Array.new(@predicates), object))
        else
          subject_as_object.add_as_object(@subject.name, object)
          add_triple(Triple.new(@subject, Array.new(@predicates), subject_as_object))
          predicate.objects[idx] = subject_as_object
        end
      end
    end

    def add_triple(triple)
      @triples << triple
    end
  end
end

require 'rdf-config/model'

class RDFConfig
  class Shex
    RDF_TYPE = 'a'.freeze

    def initialize(config, opts = {})
      @config = config
      @opts = opts

      @model = Model.instance(config)

      @indent = ' ' * 2
      @lines = prefix_lines
    end

    def generate
      @model.subjects.each do |subject|
        lines = ["<#{subject.name}Shape> {"]
        lines += rdf_type_lines(subject)
        predicates_by_subject(subject).each do |predicate|
          predicate.objects.each do |object|
            lines << "#{predicate.uri} #{node_constraint(predicate, object)}"
          end
        end
        lines << '}'

        @lines += format_lines(lines)
      end

      @lines.join("\n")
    end

    def print_warnings
      @model.print_warnings
    end

    private

    def prefix_lines
      lines = @config.prefix.each_key.map do |prefix|
        "PREFIX #{prefix}: #{@config.prefix[prefix]}"
      end
      lines << 'PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>' unless @config.prefix.keys.include?('xsd')

      lines
    end

    def rdf_type_lines(subject)
      lines = []

      predicates = rdf_type_predicates(subject)
      return lines if predicates.empty?

      predicates.each do |predicate|
        quantifier = predicate.shift
        uris = predicate.flatten
        next if uris.empty?

        constraint = if uris.size == 1
                       uris.first
                     else
                       "[#{uris.join(' ')}]"
                     end

        lines << [RDF_TYPE, constraint_text(constraint, quantifier)].join(' ')
      end

      lines
    end

    def rdf_type_predicates(subject)
      predicates = []
      subject.predicates(reject_rdf_type_variable: true).select(&:rdf_type?).each do |predicate|
        target_predicates = predicates.select { |p| p[0] == predicate.quantifier }.first
        if target_predicates.nil?
          predicates << [predicate.quantifier, rdf_type_uris(predicate)]
        else
          target_predicates << rdf_type_uris(predicate)
        end
      end

      predicates
    end


    def rdf_type_uris(rdf_type_predicate)
      rdf_type_predicate.objects.map do |object|
        object.instances.map(&:value)
      end.flatten
    end

    def predicates_by_subject(subject)
      predicate_uris = subject.predicates.reject(&:rdf_type?).map(&:uri).uniq
      predicate_uris.map do |uri|
        predicates = subject.predicates.select { |predicate| predicate.uri == uri }
        if predicates.size == 1
          predicates.first
        else
          refine_predicates(predicates)
        end
      end.reject(&:nil?).flatten
    end

    def refine_predicates(predicates)
      refined_predicates = []
      refined_predicates += refine_subject_predicates(predicates)
      refined_predicates << refine_uri_or_literal_predicates(predicates)
      refined_predicates << refine_bnode_predicates(predicates)

      refined_predicates.reject(&:nil?)
    end

    def refine_subject_predicates(predicates)
      object_subjects = predicates.map(&:objects).flatten.map(&:first_instance)
                                  .select(&:subject?)
      object_subjects.map(&:name).uniq.map do |subject_name|
        predicates_for_sort = predicates.select do |predicate|
          predicate.objects.select do |object|
            object.first_instance.name == subject_name
          end.size.positive?
        end

        sort_predicates(predicates_for_sort)
      end
    end

    def refine_uri_or_literal_predicates(predicates)
      predicates_for_sort = predicates.select do |predicate|
        predicate.objects.select do |object|
          object.first_instance.is_a?(Model::URI) || object.first_instance.is_a?(Model::Literal)
        end.size.positive?
      end

      sort_predicates(predicates_for_sort).first
    end

    def refine_bnode_predicates(predicates)
      predicates_for_sort = predicates.select do |predicate|
        predicate.objects.select do |object|
          object.first_instance.blank_node?
        end.size.positive?
      end

      sort_predicates(predicates_for_sort).first
    end

    def sort_predicates(predicates)
      predicates.sort do |a, b|
        a_num_uri_types = a.objects.map(&:uri?).size
        b_num_uri_types = b.objects.map(&:uri?).size
        if a_num_uri_types != b_num_uri_types
          b_num_uri_types <=> a_num_uri_types
        else
          a.cardinality <=> b.cardinality
        end
      end
    end

    def node_constraint(predicate, object)
      return nil if object.instance_type == 'N/A'

      if predicate.rdf_type?
        "[#{object.value}]"
      else
        case object
        when Model::Subject
          subject_constraint(predicate, object)
        else
          constraint_text(object.shex_data_type, predicate.quantifier)
        end
      end
    end

    def subject_constraint(predicate, object)
      Array(object).map do |subject|
        subject_ref = "@<#{subject.name}Shape>"
        constraint_text(subject_ref, predicate.quantifier)
      end.join(' OR ')
    end

    def constraint_text(constraint, cardinality)
      if cardinality.to_s.empty?
        constraint
      else
        [constraint, cardinality].join(' ')
      end
    end

    def format_lines(lines)
      num_lines = lines.size
      lines.map.with_index do |line, idx|
        if idx.zero? || idx == num_lines - 1
          line
        elsif idx == num_lines - 2
          [@indent, line].join
        else
          [@indent, line, ' ;'].join
        end
      end
    end
  end
end

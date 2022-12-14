require 'rdf-config/model'

class RDFConfig
  class Shex
    def initialize(config, opts = {})
      @config = config
      @opts = opts

      @model = Model.instance(config)
    end

    def generate
      lines = prefix_lines

      @model.subjects.each do |subject|
        lines << "<#{subject.name}Shape> {"
        subject.predicates.each do |predicate|
          predicate.objects.each do |object|
            lines << "  #{predicate.uri} #{node_constraint(predicate, object)} ;"
          end
        end
        lines[-1] = lines[-1][0 .. -3]
        lines << '}'
      end

      lines.join("\n")
    end

    def print_warnings
      @model.print_warnings
    end

    private

    def prefix_lines
      lines = []
      @config.prefix.keys.each do |prefix|
        lines << "PREFIX #{prefix}: #{@config.prefix[prefix]}"
      end

      unless @config.prefix.keys.include?('xsd')
        lines << 'PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>'
      end

      lines
    end

    def node_constraint(predicate, object)
      if predicate.rdf_type?
        "[#{object.value}]"
      else
        case object
        when Model::Subject
          "@<#{object.name}Shape> #{cardinality(predicate)}"
        when Model::URI
          "IRI #{cardinality(predicate)}"
        when Model::Literal
          "#{object.rdf_data_type} #{cardinality(predicate)}"
        when Model::ValueList
          case object.value.first
          when Model::Subject
            "IRI #{cardinality(predicate)}"
          when Model::Literal
            "#{object.value.map(&:rdf_data_type).uniq.join(' OR ')} #{cardinality(predicate)}"
          end
        when Model::BlankNode
          "BNode #{cardinality(predicate)}"
        end
      end
    end

    def cardinality(predicate)
      if predicate.cardinality.nil?
        ''
      else
        predicate.cardinality.label
      end
    end
  end
end

require 'rdf/turtle'

class RDFConfig
  class Convert
    class RDFGenerator
      def initialize(converter, rows, model, prefixes)
        @converter = converter
        @rows = rows
        @model = model
        @prefixes = prefixes.transform_values { |uri| RDF::URI.new(uri[1..-2]) }
        @prefixes[:xsd] = RDF::URI.new('http://www.w3.org/2001/XMLSchema#')

        @subject_node_map = {}
      end

      def generate
        RDF::Writer.for(:turtle).new(prefixes: @prefixes, canonicalize: true) do |writer|
          @rows.each do |row|
            generate_rdf_by_row(writer, row)
          end
        end
      end

      def generate_rdf_by_row(writer, row)
        @subject_node_map = {}

        converted_value = @converter.convert_row(row)
        generate_rdf_by_subject_names(writer, converted_value)
        generate_subj_pred_subj_rdf(writer)
        generate_rdf_by_object_names(writer, converted_value)
      end

      def generate_rdf_by_subject_names(writer, converted_value)
        subject_names(converted_value).each do |subject_name|
          values = converted_value[subject_name]
          next if values.empty?

          @subject_node_map[subject_name] = [] unless @subject_node_map.key?(subject_name)

          values = [values] unless values.is_a?(Array)
          values.each do |subject_value|
            node = uri_node(subject_value)
            @subject_node_map[subject_name] << node
            @model.find_subject(subject_name).types.each do |rdf_type|
              writer << RDF::Statement.new(node, RDF.type, uri_node(rdf_type))
            end
          end
        end
      end

      def generate_subj_pred_subj_rdf(writer)
        @subject_node_map.each do |subject_name, subject_nodes|
          subject_nodes.each do |as_object_node|
            @model.find_all_by_object_name(subject_name).each do |triple|
              next unless @subject_node_map.key?(triple.subject.name)

              @subject_node_map[triple.subject.name].each do |subject_node|
                writer << RDF::Statement.new(
                  subject_node, uri_node(triple.predicate.uri), as_object_node
                )
              end
            end
          end
        end
      end

      def generate_rdf_by_object_names(writer, converted_value)
        object_names(converted_value).each do |object_name|
          next unless converted_value.key?(object_name)

          values = if converted_value[object_name].is_a?(Array)
                     converted_value[object_name]
                   else
                     [converted_value[object_name]]
                   end

          values.each do |value|
            next if value.to_s.empty?

            triple = @model.find_by_object_name(object_name)
            next if triple.nil? || triple.object.is_a?(Model::Subject)

            subject_name = triple.subject.name
            next unless converted_value.key?(subject_name)

            predicate_uri = triple.predicate.uri
            prefix, local_part = predicate_uri.split(':', 2)
            predicate_uri = "#{@prefixes[prefix].to_s}#{local_part}" if @prefixes.key?(prefix)
            predicate_node = RDF::URI.new(predicate_uri)

            case triple.object
            when Model::Literal
              object_node = literal_node(value, triple.object)
            when Model::URI
              object_node = uri_node(value)
            when Model::ValueList
              object_node = uri_node(value)
            end

            @subject_node_map[subject_name].each do |subject_node|
              writer << RDF::Statement.new(subject_node, predicate_node, object_node)
            end
          end
        end
      end

      def uri_node(uri)
        prefix, local_part = uri.split(':', 2)
        if @prefixes.key?(prefix)
          RDF::URI.new("#{@prefixes[prefix].to_s}#{local_part}")
        else
          RDF::URI.new(uri)
        end
      end

      def literal_node(value, literal_object)
        case literal_object.value
        when Integer
          RDF::Literal::Integer.new(value)
        when Float
          # RDF::Literal.new(value.to_f)
          RDF::Literal::Decimal.new(value)
        when Date
          RDF::Literal::Date.new(value)
        when TrueClass, FalseClass
          RDF::Literal::Boolean.new(value)
        else
          RDF::Literal.new(value)
        end
      end

      def subject_names(converted_value)
        converted_value.keys.select { |variable_name| @model.subject?(variable_name) }
      end

      def object_names(converted_value)
        converted_value.keys.reject { |variable_name| @model.subject?(variable_name) }
      end
    end
  end
end

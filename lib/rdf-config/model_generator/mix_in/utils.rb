# frozen_string_literal: true

require 'rdf/xsd'

class RDFConfig
  class ModelGenerator
    module MixIn
      module Utils
        def object_example_value(object)
          case object
          when RDF::XSD.string
            'string'
          when RDF::XSD.int
            12345
          when RDF::XSD.float
            123.45
          when RDF::XSD.boolean
            true
          when RDF::XSD.date
            '2000-01-01'
          else
            split_uri(object).last
          end
        end

        def split_uri(uri)
          parsed_uri = URI.parse(uri)
          term = parsed_uri.fragment
          term = uri.to_s.split('/').last if term.nil?

          [uri.to_s.delete_suffix(term), term]
        end

        def qname(uri)
          prefix_uri, term = split_uri(uri)

          [@prefix[prefix_uri], term].join(':')
        end

        def camel_to_snake(str)
          # str.scan(/[A-Z][a-z0-9]*/).join('_').downcase
          str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
        end

        def snake_to_camel(str)
          # words = str.split('_')
          # words.first + words[1..-1].map(&:capitalize).join
          str.gsub(/_([A-Za-z])/) { ::Regexp.last_match(1).upcase }
        end

        def variable_name(subject_name, predicate_uri)
          _, term = split_uri(predicate_uri)

          [camel_to_snake(subject_name), camel_to_snake(term)].join('_')
        end
      end
    end
  end
end

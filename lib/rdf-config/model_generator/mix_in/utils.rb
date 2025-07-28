# frozen_string_literal: true

require 'yaml'
require 'uri'
require 'rdf/xsd'

class RDFConfig
  class ModelGenerator
    module MixIn
      module Utils
        INDENT = ' ' * 4

        def object_example_value(object)
          case object
          when RDF::XSD.string
            'string'
          when RDF::XSD.int, RDF::XSD.integer
            12345
          when RDF::XSD.float, RDF::XSD.decimal
            123.45
          when RDF::XSD.boolean
            true
          when RDF::XSD.date
            '2000-01-01'
          else
            # if @subject_name.key?(object)
            #   @subject_name[object]
            # else
              split_uri(object).last
            # end
          end
        end

        def uri_string(uri)
          uri_str = uri.to_s.strip
          if uri_str.start_with?('<') && uri_str.end_with?('>')
            uri_str[1..-2]
          else
            uri_str
          end
        end

        def split_uri(uri)
          uri_str = uri_string(uri)
          parsed_uri = URI.parse(uri_str)
          local_part = parsed_uri.fragment
          local_part = uri_str.split('/').last if local_part.nil?

          [uri_str.delete_suffix(local_part), local_part]
        end

        def camel_to_snake(str)
          # str.scan(/[A-Z][a-z0-9]*/).join('_').downcase
          str.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[_\-.:]/, '_').downcase
        end

        def snake_to_camel(snake_case_word)
          # words = snake_case_word.split('_')
          # words.first + words[1..-1].map(&:capitalize).join
          # snake_case_word.gsub(/_([A-Za-z0-9])/) { ::Regexp.last_match(1).upcase }
          snake_case_word.split(/[_\-]/).map(&:capitalize).join
        end

        def variable_name(subject_name, predicate_uri)
          namespace, local_part = split_uri(predicate_uri)

          [camel_to_snake(subject_name), prefix_for(namespace), camel_to_snake(local_part)].join('_')
        end

        def rdf_type?(uri)
          %w[a rdf:type].include?(uri.to_s) || uri.to_s == RDF.type
        end

        def indent(indent_level)
          INDENT * indent_level
        end

        def change_extension(path, new_extension)
          path.sub(/\.[^.]+\z/, new_extension)
        end
      end
    end
  end
end

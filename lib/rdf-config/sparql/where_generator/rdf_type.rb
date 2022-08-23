class RDFConfig
  class SPARQL
    class WhereGenerator
      module RDFType
        def has_rdf_type?
          case rdf_types
          when String
            !rdf_types.strip.empty?
          when Array
            !rdf_types.flatten.uniq.first.nil?
          else
            false
          end
        end

        def has_one_rdf_type?
          has_rdf_type? && (rdf_types.instance_of?(String) || rdf_types.size == 1)
        end

        def has_multiple_rdf_types?
          has_rdf_type? && rdf_types.size > 1
        end

        def rdf_types=(rdf_types)
          @rdf_types = case rdf_types
                       when Array
                         rdf_types
                       when String
                         [rdf_types]
                       end
        end

        def rdf_type
          @rdf_types.first
        end
      end
    end
  end
end

class RDFConfig
  class SPARQL
    class WhereGenerator
      class BlankNode
        include RDFType

        attr_reader :predicate_routes, :rdf_types

        def initialize(bnode_id, predicate_routes)
          @bnode_id = bnode_id
          @predicate_routes = predicate_routes
        end

        def name
          "_b#{@bnode_id}"
        end

        def to_sparql(**opts)
          "_:b#{@bnode_id}"
        end

        def rdf_type_varname
          "?#{name}__class"
        end

        def ==(other)
          name == other.name
        end

        def bnode?
          true
        end
      end
    end
  end
end

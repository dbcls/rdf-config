class RDFConfig
  class SPARQL
    class WhereGenerator
      class Variable
        include RDFType

        attr_reader :name, :rdf_types

        def initialize(name, opts = {})
          @name = name
          @variable_name_prefix = opts.key?(:variable_name_prefix) ? opts[:variable_name_prefix] : ''
          @sparql_variable_name =
            opts.key?(:sparql_variable_name) ? opts[:sparql_variable_name] : "?#{@variable_name_prefix}#{name}"
        end

        def to_sparql(**opts)
          case name
          when Array
            name.to_s
          else
            @sparql_variable_name
          end
        end

        def rdf_type_varname
          "#{to_sparql}__class"
        end

        def ==(other)
          @name == other.name
        end

        def bnode?
          false
        end
      end
    end
  end
end

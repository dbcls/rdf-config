class RDFConfig
  class SPARQL
    class SelectGenerator < SPARQL
      def initialize(config, opts = {})
        super
      end

      def generate
        [%(SELECT #{variables.map { |name| sparql_varname(name) }.join(' ')})]
      end

      private

      def sparql_varname(variable_name)
        triple = model.find_by_object_name(variable_name)
        case triple.object
        when Model::Subject
          "?#{triple.object.as_object_value(triple.subject.name)}"
        else
          "?#{triple.object.name}"
        end
      end
    end
  end
end

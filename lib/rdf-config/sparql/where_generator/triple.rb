class RDFConfig
  class SPARQL
    class WhereGenerator
      class Triple
        attr_reader :subject, :predicate, :object

        def initialize(subject, predicate, object)
          @subject = subject
          @predicate = predicate
          @object = if object.is_a?(Array) && object.size == 1
                      object.first
                    else
                      object
                    end
        end

        def rdf_type?
          %w[a rdf:type].include?(@predicate)
        end

        def to_sparql(**opts)
          indent = opts.key?(:indent) ? opts[:indent] : ''
          is_first_triple = opts.key?(:is_first_triple) ? opts[:is_first_triple] : true
          is_last_triple = opts.key?(:is_last_triple) ? opts[:is_last_triple] : true
          left_indent = opts.key?(:left_indent) ? opts[:left_indent] : ''
          line = if is_first_triple
                   "#{left_indent}#{indent}#{subject.to_sparql} "
                 else
                   "#{left_indent}#{indent * 2}"
                 end
          line = if rdf_type?
                   if object.has_one_rdf_type?
                     "#{line}a #{object.rdf_type}"
                   else
                     "#{line}a #{object.rdf_type_varname}"
                   end
                 else
                   "#{line}#{predicate} #{object.to_sparql(**opts)}"
                 end

          "#{line} #{is_last_triple ? '.' : ';'}"
        end

        def ==(other)
          @subject.to_sparql == other.subject.to_sparql &&
            @predicate == other.predicate &&
            @object.to_sparql == other.object.to_sparql
        end

        def to_s
          "#{subject.to_sparql} #{predicate} #{object.to_sparql}"
        end
      end
    end
  end
end

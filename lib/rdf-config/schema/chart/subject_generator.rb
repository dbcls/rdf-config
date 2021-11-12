require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'

class RDFConfig
  class Schema
    class Chart
      class SubjectGenerator
        def initialize(subject, pos, opts = {})
          @subject = subject
          @pos = pos

          @drawing_mode = opts.key?(:drawing_mode) ? opts[:drawing_mode] : :subject
          @nest = opts.key?(:nest) ? opts[:nest] : false
          @model = opts.key?(:model) ? opts[:model] : nil
        end

        def generate
          generator = if @subject.blank_node?
                        BlankNodeGenerator.new(@pos)
                      else
                        URINodeGenerator.new(
                          @subject, @pos, drawing_mode: @drawing_mode, nest: @nest, model: @model
                        )
                      end

          generator.generate
        end
      end
    end
  end
end

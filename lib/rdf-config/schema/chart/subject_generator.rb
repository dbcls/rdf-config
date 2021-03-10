require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'

class RDFConfig
  class Schema
    class Chart
      class SubjectGenerator
        def initialize(subject, pos, opts = {})
          @subject = subject
          @pos = pos

          @disp_mode = opts.key?(:disp_mode) ? opts[:disp_mode] : :subject
        end

        def generate
          generator = if @subject.blank_node?
                        BlankNodeGenerator.new(@pos)
                      else
                        URINodeGenerator.new(@subject, @pos, disp_mode: @disp_mode)
                      end

          generator.generate
        end
      end
    end
  end
end

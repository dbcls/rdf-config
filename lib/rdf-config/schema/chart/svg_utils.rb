class RDFConfig
  class Schema
    class Chart
      module SvgUtils
        def xml_doc
          doc = REXML::Document.new
          doc.add REXML::XMLDecl.new('1.0', 'UTF-8')
          doc.add REXML::DocType.new('svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"')

          doc
        end

        def generate_svg_element
          @svg_element = REXML::Element.new('svg')
          @svg_element.add_attribute('xmlns', 'http://www.w3.org/2000/svg')
          @svg_element.add_attribute('style', 'background-color: rgb(255, 255, 255);')
        end

        def add_to_svg(element, element_to_add = @svg_element)
          case element
          when Array
            element.each do |elem|
              element_to_add.add_element(elem)
            end
          else
            element_to_add.add_element(element)
          end
        end

        def output_svg(width, height, viewbox_x = -0.5, viewbox_y = -0.5)
          svg_opts = {
            width: "#{width}px",
            height: "#{height}px",
            viewBox: "#{viewbox_x} #{viewbox_y} #{width} #{height}"
          }
          @svg_element.add_attribute_by_hash(svg_opts)

          xml = xml_doc
          xml.add_element(@svg_element)
          xml.write($stdout, 2)
        end

        def model
          @model ||= Model.instance(@config)
        end

        def sort_subjects(subjects)
          subj_names = model.subjects.map(&:name)
          subjects.sort { |a, b| subj_names.index(a.name) <=> subj_names.index(b.name) }
        end

        def sort_object_names(subject, object_names)
          obj_names = subject.object_names
          object_names.sort { |a, b| obj_names.index(a) <=> obj_names.index(b) }
        end
      end
    end
  end
end

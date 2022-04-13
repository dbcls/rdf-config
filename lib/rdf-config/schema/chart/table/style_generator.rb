require 'rdf-config/schema/chart/table/element_generator'

class RDFConfig
  class Schema
    class Chart
      class Table
        class StyleGenerator < ElementGenerator
          def initialize
          end

          def generate
            defs = REXML::Element.new('defs')
            style = REXML::Element.new('style')
            style.add_attribute('type', 'text/css')
            style.add_text(<<~STYLE)
              .subject-wrapper {
                  fill: #fff;
                  stroke-width: 2px;
                  stroke: #000;
              }

              .subject {
                  /* do not delete */
              }

              .subject-area {
                  fill: #5a4838;
              }

              .subject-text {
                  fill: #fff;
                  font-size: #{FONT_SIZE}px;
                  font-family: HelveticaLTStd-Bold, Helvetica LT Std;
              }

              .subject-link {
                  fill: #ffce9f;
              }

              .resource {
                  fill: #ccf8f8;
              }

              .literal {
                  fill: #f8cecc;
              }

              .unknown {
                  fill: #e0e0e0;
              }

              .text {
                  font-size: #{FONT_SIZE}px;
                  font-family: "Helvetica Neue", Arial, sans-serif;
              }

              .black-stroke {
                  stroke: #0000;
              }

              .blank-node {
                  fill: #f2f2e9;
                  stroke: #000;
                  stroke-dasharray: 0 0 2.5 2.5;
              }
            STYLE

            defs.add_element(style)

            defs
          end
        end
      end
    end
  end
end

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
              .table-container {
                  fill: #fff;
                  stroke-width: 2px;
                  stroke: #000;
              }

              .subject-container {
                  fill: #5a4838;
              }

              .subject-type {
                  fill: #fff;
                  font-size: #{FONT_SIZE}px;
                  font-family: Helvetica, Arial, sans-serif;
              }

              .subject-text {
                  font-weight: bold;
                  opacity: 0.8;
                  fill: #fff;
                  font-size: #{FONT_SIZE}px;
                  font-family: Helvetica, Arial, sans-serif;
              }

              .uri-object {
                  fill: #ccf8f8;
              }

              .literal-object {
                  fill: #f8cecc;
              }

              .blank-node-object {
                  fill: #f2f2e9;
                  stroke: #000;
                  stroke-dasharray: 0 0 2.5 2.5;
              }

              .subject-object {
                  fill: #ffce9f;
              }

              .unknown-object {
                  fill: #e0e0e0;
              }

              .object-type {
                  font-weight: bold;
                  opacity: 0.8;
                  fill: #666;
                  font-size: #{FONT_SIZE}px;
                  font-family: Helvetica, Arial, sans-serif;
              }

              .object-text {
                  font-size: #{FONT_SIZE}px;
                  font-family: Helvetica, Arial, sans-serif;
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

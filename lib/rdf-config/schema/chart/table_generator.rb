require 'rdf-config/schema/chart/svg_utils'

class RDFConfig
  class Schema
    class Chart
      class TableGenerator
        include SvgUtils

        START_X = 20
        START_Y = 20

        FONT_SIZE = 14

        SUBJECT_HEIGHT = 26
        OBJECT_HEIGHT = 26
        OUTER_STROKE_WIDTH = 3
        SEPARATOR_STROKE_WIDTH = 1

        TABLE_PADDING_LEFT = 10
        TABLE_PADDING_RIGHT = 10
        TABLE_SPACING = 20

        BEZIER_ADJ = 18

        def initialize(config, opts = {})
          @config = config
          @opts = opts

          @top_g_element = REXML::Element.new('g')
          text_widths = []
          subjects.each do |subject_hash|
            text_widths << text_width("#{subject_hash[:name]} #{subject_hash[:rdf_type]}")
            subject_hash[:object_names].each do |object_name|
              text_widths << text_width(object_name)
            end
          end
          @table_width = text_widths.max

          @table_idx = 0
          @current_x = START_X
          @current_y = [START_Y, START_Y - TABLE_SPACING, START_Y - TABLE_SPACING]

          @table_x = START_X
          @table_y = START_Y
          @last_object_y = 0
        end

        def generate
          generate_svg_element
          add_to_svg(style_element)
          add_to_top_wrapper(generate_tables)
          add_to_svg(@top_g_element)
          output_svg(START_X + (@table_width + TABLE_SPACING) * @current_y.size, @current_y.max + TABLE_SPACING)
        end

        private

        def generate_tables
          table_elements = []
          @subjects.each do |subject_hash|
            table_elements << generate_table(subject_hash)
          end

          table_elements
        end

        def generate_table(subject_hash)
          wrapper = REXML::Element.new('g')
          wrapper.add_element(generate_subject(subject_hash))

          subject_hash[:object_names].each do |object_name|
            if subject_hash[:object_names].last == object_name
              wrapper.add_element(generate_last_object(object_name))
            else
              wrapper.add_element(generate_object(object_name))
            end
          end

          wrapper.add_element(generate_outer_frame)

          move_to_next_table

          wrapper
        end

        def generate_subject(subject_hash)
          g = REXML::Element.new('g')
          g.add_element(generate_subject_path)
          g.add_element(generate_subject_name(subject_hash))
          g.add_element(generate_subject_rdf_type(subject_hash))

          move_to_first_object
          g.add_element(generate_separator)

          g
        end

        def generate_subject_path
          path = REXML::Element.new('path')
          d_attrs = [
            "M #{@current_x},#{@current_y[lane_idx] + SUBJECT_HEIGHT}",
            "v -#{BEZIER_ADJ}",
            "q 0,-#{SUBJECT_HEIGHT - BEZIER_ADJ} #{SUBJECT_HEIGHT - BEZIER_ADJ},-#{SUBJECT_HEIGHT - BEZIER_ADJ}",
            "h #{@table_width - (SUBJECT_HEIGHT - BEZIER_ADJ) * 2}",
            "q #{SUBJECT_HEIGHT - BEZIER_ADJ},0 #{SUBJECT_HEIGHT - BEZIER_ADJ},#{SUBJECT_HEIGHT - BEZIER_ADJ}",
            "v #{BEZIER_ADJ}"
          ]
          path.add_attribute_by_hash(
            d: d_attrs.join(' '),
            class: 'subject frame'
          )

          path
        end

        def generate_subject_name(subject_hash)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: name_x_position,
            y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
            class: 'text -header'
          )
          text.add_text(subject_hash[:name])

          text
        end

        def generate_subject_rdf_type(subject_hash)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: @table_x + @table_width - TABLE_PADDING_RIGHT,
            y: text_y_position(SUBJECT_HEIGHT, FONT_SIZE),
            'text-anchor' => 'end',
            class: 'text -header'
          )
          text.add_text(subject_hash[:rdf_type])

          text
        end

        def generate_object(object_name)
          g = REXML::Element.new('g')
          rect = REXML::Element.new('rect')
          rect.add_attribute_by_hash(
            x: @current_x, y: @current_y[lane_idx],
            width: @table_width,
            height: OBJECT_HEIGHT,
            class: "#{style_class_by_object(object_name)}"
          )
          g.add_element(rect)
          g.add_element(generate_object_name(object_name))

          move_to_next_object
          g.add_element(generate_separator)

          g
        end

        def generate_last_object(object_name)
          @last_object_y = @current_y[lane_idx]

          g = REXML::Element.new('g')
          path = REXML::Element.new('path')
          d_attrs = [
            "M #{@current_x + @table_width},#{@current_y[lane_idx]}",
            "v 0,#{BEZIER_ADJ}",
            "q 0,#{SUBJECT_HEIGHT - BEZIER_ADJ} -#{SUBJECT_HEIGHT - BEZIER_ADJ},#{SUBJECT_HEIGHT - BEZIER_ADJ}",
            "h -#{@table_width - (SUBJECT_HEIGHT - BEZIER_ADJ) * 2}",
            "q -#{SUBJECT_HEIGHT - BEZIER_ADJ},0 -#{SUBJECT_HEIGHT - BEZIER_ADJ},-#{SUBJECT_HEIGHT - BEZIER_ADJ}",
            "v -#{BEZIER_ADJ}"
          ]
          path.add_attribute_by_hash(
            d: d_attrs.join(' '),
            class: "#{style_class_by_object(object_name)} frame"
          )
          g.add_element(path)
          g.add_element(generate_object_name(object_name))

          move_to_next_object

          g
        end

        def generate_object_name(object_name)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: name_x_position,
            y: text_y_position(OBJECT_HEIGHT, FONT_SIZE),
            class: 'text'
          )
          text.add_text(object_name)

          text
        end

        def style_class_by_object(object_name)
          case model.find_object(object_name)
          when Model::Subject
            style_class = 'resource'
          when Model::URI
            style_class = 'resource'
          when Model::Literal
            style_class = 'literal'
          else
            style_class = 'literal'
          end

          style_class
        end

        def generate_outer_frame
          path = REXML::Element.new('path')
          d_attrs = [
            "M #{@table_x},#{@table_y + SUBJECT_HEIGHT}",
            "V #{@last_object_y}",
            "M #{@table_x + @table_width},#{@table_y + SUBJECT_HEIGHT}",
            "V #{@last_object_y}"
          ]
          path.add_attribute_by_hash(
            d: d_attrs.join(' '),
            class: 'frame'
          )

          path
        end

        def generate_separator
          line = REXML::Element.new('line')
          line.add_attribute_by_hash(
            x1: @current_x, y1: @current_y[lane_idx],
            x2: @current_x + @table_width, y2: @current_y[lane_idx],
            class: 'separator'
          )
          @current_y[lane_idx] += SEPARATOR_STROKE_WIDTH

          line
        end

        def add_to_top_wrapper(element)
          case element
          when Array
            element.each do |elem|
              @top_g_element.add_element(elem)
            end
          else
            @top_g_element.add_element(element)
          end
        end

        def name_x_position
          @current_x + TABLE_PADDING_LEFT
        end

        def text_y_position(rect_height, font_size)
          @current_y[lane_idx] + (rect_height - 3) - (rect_height - font_size) / 2
        end

        def move_to_next_table
          @table_idx += 1
          @current_x = START_X + (@table_width + TABLE_SPACING) * lane_idx
          @current_y[lane_idx] += TABLE_SPACING

          @table_x = @current_x
          @table_y = @current_y[lane_idx]
        end

        def move_to_first_object
          @current_y[lane_idx] += SUBJECT_HEIGHT
        end

        def move_to_next_object
          @current_y[lane_idx] += OBJECT_HEIGHT
        end

        def lane_idx
          @table_idx % @current_y.size
        end

        def text_width(text)
          text_chars = text.to_s.chars

          wide_width_chars = text_chars.select { |char| %w[C D Q R S].include?(char) }
          narrow_width_chars = text_chars.select { |char| %w[f i j l t :].include?(char) }

          (FONT_SIZE * 0.7) * wide_width_chars.size + (FONT_SIZE * 0.2) * narrow_width_chars.size +
            (FONT_SIZE * 0.5) * (text_chars.size - wide_width_chars.size - narrow_width_chars.size)
        end

        def style_element
          defs = REXML::Element.new('defs')
          style = REXML::Element.new('style')
          style.add_attribute('type', 'text/css')
          style.add_text(<<-STYLE)
.subject {
    fill: #665240;
}

.literal {
    fill: #f8cecc;
}

.resource {
    fill: #ffce9f;
}

.text {
    fill: #3e3532;
    font-size: #{FONT_SIZE}px;
    font-family: "Helvetica Neue", Arial, sans-serif;
}

.-header {
    fill: #fff;
}

.separator {
    fill: none;
    stroke-miterlimit: 10;
}

.separator {
    stroke: rgba(0,0,0,.7);
}

.frame {
    stroke: #000;
    stroke-width: #{OUTER_STROKE_WIDTH}px;
    stroke-miterlimit: 10;
}
STYLE

          defs.add_element(style)

          defs
        end

        def subjects
          @subjects ||= if variables.empty?
                          all_subject_hashes
                        else
                          subjects_by_variables
                        end
        end

        def variables
          @variables ||= if @opts.key?(:variables) && @opts[:variables].is_a?(Array) && !@opts[:variables].empty?
                           @opts[:variables]
                         else
                           []
                         end
        end

        def all_subject_hashes
          subject_hashes = []
          model.subjects.each do |subject|
            subject_hashes << {
              name: subject.name,
              rdf_type: subject.type,
              object_names: subject.object_names.select { |name| name.is_a?(String) }
            }
          end

          subject_hashes
        end

        def subjects_by_variables
          valid_subjects = []
          object_names = {}
          variables.each do |variable_name|
            subject = model.find_subject(variable_name)
            if subject.nil?
              triple = model.find_by_object_name(variable_name)
              unless triple.nil?
                subj = triple.subject
                valid_subjects << triple.subject unless valid_subjects.map(&:name).include?(subj.name)
                unless object_names.key?(subj.name)
                  object_names[subj.name] = []
                end
                object_names[subj.name] << variable_name
              end
            else
              valid_subjects << subject
            end
          end

          subject_hashes = []
          sort_subjects(valid_subjects).each do |subj|
            obj_names = if object_names.key?(subj.name)
                          sort_object_names(subj, object_names[subj.name])
                        else
                          subj.object_names
                        end
            subject_hashes << {
              name: subj.name,
              rdf_type: subj.type,
              object_names: obj_names
            }
          end

          subject_hashes
        end
      end
    end
  end
end

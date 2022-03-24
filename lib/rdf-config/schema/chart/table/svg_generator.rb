require 'rdf-config/schema/chart/svg_utils'
require 'rdf-config/schema/chart/table/constant'
require 'rdf-config/schema/chart/table/element_generator'
require 'rdf-config/schema/chart/table/style_generator'
require 'rdf-config/schema/chart/table/table_generator'
require 'rdf-config/schema/chart/table/subject_generator'
require 'rdf-config/schema/chart/table/blank_node_generaotr'
require 'rdf-config/schema/chart/table/object_generator'

class RDFConfig
  class Schema
    class Chart
      class Table
        class SvgGenerator
          include SvgUtils
          include Constant

          @table_idx = 0
          @table_x = START_X
          @table_y = [START_Y]

          @current_x = START_X
          @y_positions = [START_Y, START_Y - TABLE_SPACING, START_Y - TABLE_SPACING]
          @last_object_y = 0

          @table_width = 480

          @bnode_number = 1
          @bnode_indent = 0

          class << self
            attr_reader :y_positions, :last_object_y, :table_width

            def generate_table(subject)
              if subject.blank_node?
                increase_bnode_indent
                generator = BlankNodeGenerator.new(
                  subject, @table_x + Constant::SUBJECT_WRAPPER_PADDING, current_y, bnode_table_width,
                  table_x: @table_x, table_y: table_y
                )
                table_element = generator.generate
                decrease_bnode_indent
              else
                generator = TableGenerator.new(
                  subject, @current_x, current_y, table_width,
                  table_x: @table_x, table_y: table_y
                )
                table_element = generator.generate
              end

              table_element
            end

            def generate_subject(subject)
              generator = SubjectGenerator.new(
                subject, @table_x, @table_y.last, table_width, table_xpos: @table_x
              )

              generator.generate
            end

            def generate_object(object, is_last: false)
              @last_object_y = current_y if is_last

              object_generator = ObjectGenerator.new(
                # object, @current_x, current_y, table_width, is_last: is_last, bnode_ident: @bnode_indent
                object, @table_x + Constant::SUBJECT_WRAPPER_PADDING, current_y, table_width,
                is_last: is_last, bnode_ident: @bnode_indent
              )
              object_element = object_generator.generate

              move_to_next_object

              object_element
            end

            def move_to_next_table
              @table_idx += 1
              @current_x = SvgGenerator::START_X + (table_width + SvgGenerator::TABLE_SPACING) * lane_idx
              @y_positions[lane_idx] += SvgGenerator::TABLE_SPACING

              @table_x = @current_x
              @table_y = [current_y]
            end

            def move_to_first_object
              @y_positions[lane_idx] += SvgGenerator::SUBJECT_HEIGHT
              @y_positions[lane_idx] += Constant::SUBJECT_WRAPPER_PADDING unless in_bnode?

            end

            def move_to_next_object
              @y_positions[lane_idx] += (SvgGenerator::OBJECT_HEIGHT + Constant::OBJECT_MARGIN)
            end

            def move_to_next_object_after_bnode
              @y_positions[lane_idx] += Constant::OBJECT_MARGIN
            end

            def lane_idx
              @table_idx % @y_positions.size
            end

            def current_y
              @y_positions[lane_idx]
            end

            def table_y
              @table_y.last
            end

            def bnode_table_width
              table_width -
                (Constant::SUBJECT_WRAPPER_PADDING * 2) -
                Constant::BLANK_NODE_LEFT_MARGIN * (@bnode_indent - 1)
            end

            def increase_bnode_indent
              if @bnode_indent.positive?
                @current_x += Constant::BLANK_NODE_LEFT_MARGIN
                @table_x +=  Constant::BLANK_NODE_LEFT_MARGIN
                @table_width -= Constant::BLANK_NODE_LEFT_MARGIN
              end
              @table_y.push(current_y)
              @bnode_indent += 1
            end

            def decrease_bnode_indent
              if @bnode_indent > 1
                @current_x -= Constant::BLANK_NODE_LEFT_MARGIN
                @table_x -=  Constant::BLANK_NODE_LEFT_MARGIN
                @table_width += Constant::BLANK_NODE_LEFT_MARGIN
              end
              @table_y.pop
              @bnode_indent -= 1
              move_to_next_object_after_bnode
            end

            def in_bnode?
              @bnode_indent.positive?
            end
          end

          def initialize(config, opts = {})
            @config = config
            @opts = opts

            @top_element = REXML::Element.new('g')

            @bnode_idx = 1
            @subjects = []
            fetch_subjects
          end

          def generate
            generate_svg_element
            add_to_svg(generate_style)
            add_to_top_element(generate_tables)
            add_to_svg(@top_element)
            output_svg(
              START_X + (SvgGenerator.table_width + TABLE_SPACING) * SvgGenerator.y_positions.size,
              SvgGenerator.y_positions.max + TABLE_SPACING
            )
          end

          private

          def generate_tables
            table_elements = []
            @subjects.reject(&:blank_node?).each do |subject|
              table_elements << self.class.generate_table(subject)

              self.class.move_to_next_table unless subject.blank_node?
            end

            table_elements
          end

          def generate_style
            generator = StyleGenerator.new

            generator.generate
          end

          def fetch_subjects
            model.subjects.each do |subject|
              add_subject(subject)
            end
          end

          def add_subject(subject)
            if subject.blank_node?
              subject.bnode_name = bnode_name
              @bnode_idx += 1
            end

            @subjects << subject

            bnode_objects = subject.objects.select { |object| object.blank_node? && object.value.is_a?(Model::Subject) }
            return if bnode_objects.empty?

            bnode_objects.each do |bnode_object|
              add_subject(bnode_object.value)
            end
          end

          def bnode_name
            "[blank_node#{@bnode_idx}]"
          end

          def calc_table_width
            text_widths = []

            @subjects.each do |subject|
              text_widths << ElementGenerator.calc_text_width(SubjectGenerator.element_text(subject).to_s)
              subject.objects(reject_rdf_type: true).each do |object|
                text_widths << ElementGenerator.calc_text_width(ObjectGenerator.object_name(object))
              end
            end

            text_widths.max
          end

          def add_to_top_element(element)
            case element
            when Array
              element.each do |elem|
                @top_element.add_element(elem)
              end
            else
              @top_element.add_element(element)
            end
          end
        end
      end
    end
  end
end

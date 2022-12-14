require 'rdf-config/schema/chart/svg_utils'

class RDFConfig
  class Schema
    class Chart
      class ArcGenerator
        include Math
        include SvgUtils

        RADIUS = 300
        ITEM_CIRCLE_RADIUS = 5
        ITEM_CIRCLE_MARGIN = 4
        SUBJECT_FONT_FAMILY = 'Arial-BoldMT'
        SUBJECT_FONT_SIZE = 14
        GLYPH_HEIGHT = 3

        def initialize(config, opts = {})
          @config = config
          @opts = opts

          @variables = (opts[:variables] if opts.key?(:variables))
          @num_subjects = subjects.size
          @width, @height = calc_size
        end

        def generate
          generate_svg_element
          add_to_svg(style_element)
          generate_top_g_element
          # generate_grid
          generate_subjects
          generate_relations
          add_to_svg(@top_g_element)

          output_svg(@width, @height, RADIUS * -1, RADIUS * -1)
        end

        private

        def subjects
          @subjects ||= if @variables.is_a?(Array) && !@variables.empty?
                          model.subjects & subjects_by_variables(@variables)
                        else
                          model.subjects
                        end
        end

        def subjects_by_variables(variables)
          subject_names = []
          variables.each do |variable_name|
            if model.subject?(variable_name)
              subject_name = variable_name
            else
              triple = model.find_by_object_name(variable_name)
              next if triple.nil?

              subject_name = triple.subject.name
            end

            subject_names << subject_name
          end

          subject_names.uniq.map { |subject_name| model.find_subject(subject_name) }
        end

        def related_subjects(subject)
          subjects = []
          subject.objects.each do |object|
            case object
            when Model::Subject
              subjects << object
            when Model::ValueList
              object.value.each do |obj|
                subjects << obj if obj.is_a?(Model::Subject)
              end
            end
          end

          subjects
        end

        def generate_top_g_element
          @top_g_element = REXML::Element.new('g')
          @top_g_element.add_attribute_by_hash(
            transform: "rotate(-90.0,#{RADIUS},#{RADIUS})"
          )
        end

        def generate_subjects
          subjects.each do |subject|
            add_to_svg(generate_subject(subject), @top_g_element)
          end
        end

        def generate_subject(subject)
          g = REXML::Element.new('g')
          g.add_attribute_by_hash(
            transform: "rotate(#{subject_rotate_deg(subject)},#{RADIUS},#{RADIUS})"
          )
          g.add_element(subject_item_circle)
          g.add_element(subject_text_element(subject))

          g
        end

        def subject_item_circle
          circle = REXML::Element.new('circle')
          circle.add_attribute_by_hash(
            cx: RADIUS * 2 + ITEM_CIRCLE_RADIUS,
            cy: RADIUS,
            r: ITEM_CIRCLE_RADIUS,
            fill: '#000'
          )

          circle
        end

        def subject_text_element(subject)
          text = REXML::Element.new('text')
          text.add_attribute_by_hash(
            x: RADIUS * 2 + ITEM_CIRCLE_RADIUS * 2 + ITEM_CIRCLE_MARGIN,
            y: RADIUS + SUBJECT_FONT_SIZE / 2 - GLYPH_HEIGHT,
            class: 'subject-name'
          )
          text.add_text(subject.name)

          text
        end

        def generate_relations
          subjects.each do |subject|
            generate_relations_by_subject(subject)
          end
        end

        def generate_relations_by_subject(subject)
          related_subjects(subject).each do |subject_as_object|
            next unless subjects.include?(subject_as_object)

            generate_relation(subject, subject_as_object)
          end
        end

        def generate_relation(subject, subject_as_object)
          return if subject.name == subject_as_object.name

          subject_x, subject_y = subject_position(subject)
          object_x, object_y = subject_position(subject_as_object)

          path = REXML::Element.new('path')
          path.add_attribute_by_hash(
            d: "M #{subject_x},#{subject_y} Q #{RADIUS} #{RADIUS} #{object_x} #{object_y}",
            class: 'relation'
          )

          add_to_svg(path, @top_g_element)
        end

        def generate_grid
          generate_vertical_grid(20)
          generate_horizontal_grid(20)
        end

        def generate_vertical_grid(step)
          0.step(@width, step) do |pos|
            line = REXML::Element.new('line')
            line.add_attribute_by_hash(
              x1: pos, y1: 0, x2: pos, y2: @height,
              class: 'grid'
            )
            add_to_svg(line)
          end
        end

        def generate_horizontal_grid(step)
          0.step(@height, step) do |pos|
            line = REXML::Element.new('line')
            line.add_attribute_by_hash(
              x1: 0, y1: pos, x2: @width, y2: pos,
              class: 'grid'
            )
            add_to_svg(line)
          end
        end

        def style_element
          style = REXML::Element.new('style')
          style.add_attribute('type', 'text/css')
          style.add_text(<<~STYLE)
            .subject-name { font-family:'#{SUBJECT_FONT_FAMILY}'; font-size:#{SUBJECT_FONT_SIZE}px; }
            .relation { fill:none; stroke:#000000; }
            .grid { stroke:#CCCCCC; stroke-width:1px;}
          STYLE

          style
        end

        def subject_rotate_deg(subject)
          360.0 / @num_subjects * subject_idx(subject)
        end

        def subject_position(subject)
          rad = 2 * PI * (subject_idx(subject) / @num_subjects.to_f)
          x = RADIUS.to_f + RADIUS * cos(rad)
          y = RADIUS.to_f + RADIUS * sin(rad)

          [x, y]
        end

        def subject_idx(subject)
          unless @subject_idx.is_a?(Hash)
            @subject_idx = {}
            subjects.each_with_index do |subj, idx|
              @subject_idx[subj.name] = idx
            end
          end

          @subject_idx[subject.name]
        end

        def calc_size
          [1500, 1500]
        end
      end
    end
  end
end

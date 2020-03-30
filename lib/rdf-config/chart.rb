class RDFConfig

  class Chart
    def initialize(model)
      @model = model
    end

    class Senbero < Chart
      def initialize(model)
        super
      end

      def color_subject(str)
        "\033[35m#{str}\033[0m"
      end

      def color_predicate(str)
        "\033[33m#{str}\033[0m"
      end

      def color_object(str)
        "\033[36m#{str}\033[0m"
      end

      def generate
        seen = {}
        @model.subjects.each do |subject|
          subject_class = @model.subject_type_map[subject]
          subject_color = color_subject(subject)
          puts "#{subject_color} (#{subject_class})"
          predicates = @model.predicates[subject]
          predicates.each_with_index do |predicate, i|
            if seen[predicate]
              next
            else
              seen[predicate] = true
            end
            predicate_color = color_predicate(predicate)
            if i < predicates.size - 1
              puts "    |-- #{predicate_color}"
            else
              puts "    `-- #{predicate_color}"
            end
            objects = @model.objects[subject][predicate]
            objects.each_with_index do |object, j|
              object_label_value = @model.object_label_map[subject][object]
              case @model.object_type(object)
              when :uri
                object_label = object_label_value
              when :literal
                object_label =  object_label_value.inspect
              else
                "N/A"
              end
              object_color = color_object(object)
              object_color = color_subject(object) if @model.subjects.include?(object)
              if i < predicates.size - 1
                if j < objects.size - 1
                  puts "    |       |-- #{object_color} (#{object_label})"
                else
                  puts "    |       `-- #{object_color} (#{object_label})"
                end
              else
                if j < objects.size - 1
                  puts "            |-- #{object_color} (#{object_label})"
                else
                  puts "            `-- #{object_color} (#{object_label})"
                end
              end
            end
          end
        end
      end
    end

    class Schema < Chart
      require 'rexml/document'
      class REXML::Element
        def add_attribute_by_hash(attr_hash)
          attr_hash.each do |name, value|
            add_attribute(name.to_s, value)
          end
        end
      end

      require 'rdf-config/chart/svg_element_opt'
      require 'rdf-config/chart/svg_element'
      include SVGElementOpt
      include SVGElement

      Point = Struct.new(:x, :y)
      ArrowPosition = Struct.new(:x1, :y1, :x2, :y2)

      START_X = 50.freeze
      START_Y = 10.freeze
      YPOS_CHANGE_NUM_OBJ = 8.freeze

      def initialize(model)
        super

        @svg_element = svg_element
        @current_pos = Point.new(START_X, START_Y)
        @subject_ypos = START_Y
        @object_pos = {}
        @num_objects = 0
        @generated_subjects = []
        @object_positions = []
      end

      def generate
        @model.yaml.each do |subject_hash|
          subject = Model::Subject.new(subject_hash, @model.prefix)

          @num_objects = 0
          generate_subject(subject)
          @current_pos.x = START_X
          @subject_ypos = @current_pos.y
        end

        output_svg
      end

      def generate_subject(subject)
        return if @generated_subjects.include?(subject.name)

        if @object_pos.key?(subject.name)
          # move to subject rectangle position
          @current_pos.x = @object_pos[subject.name].x
          @current_pos.y = @subject_ypos = @object_pos[subject.name].y
        else
          # draw subject rectangle
          inner_texts = [subject.name, subject.value]
          add_to_svg(uri_elements(@current_pos, inner_texts, :instance))
        end

        move_to_predicate
        subject.property_hash.each do |property_hash|
          generate_property(subject, property_hash)
        end

        @generated_subjects << subject.name
      end

      def generate_property(subject, property_hash)
        key = property_hash.keys.first
        predicate = Model::Predicate.new(key)
        objects = property_hash[key]

        case objects
        when String
          if predicate.rdf_type?
            # objects is rdf:type URI
            generate_rdf_type(objects)
          else
            # If the objects is a string, consider it a object name
            generate_predicate(predicate)
            generate_object(Model::Object.instance(objects, @model.prefix))
          end
        when Array
          if predicate.rdf_type?
            objects.each do |rdf_type|
              generate_rdf_type(rdf_type)
            end
          else
            objects.each do |object_hash|
              generate_object_by_hash(subject, predicate, object_hash)
            end
          end
        end
      end

      def generate_object_by_hash(subject, predicate, object_hash)
        object = Model::Object.instance(object_hash, @model.prefix)
        if object.blank_node?
          generate_blank_node(subject, predicate, object_hash[object.name])
        else
          generate_predicate(predicate)

          if subject_name?(object.name)
            subject_hash = subject_config(object.name)
            if subject_hash.empty?
              generate_object(object)
            else
              generate_object_as_subject(subject_hash)
            end
          else
            generate_object(object)
          end
        end
      end

      def generate_object_as_subject(subject_hash)
        subject = Model::Subject.new(subject_hash, @model.prefix)
        @current_pos.x = @current_pos.x + PREDICATE_AREA_WIDTH
        prev_subject_ypos = @subject_ypos
        @subject_ypos = @current_pos.y
        prev_num_objects = @num_objects
        @num_objects = 0
        generate_subject(subject)
        @current_pos.x = @current_pos.x - (PREDICATE_AREA_WIDTH + RECT_WIDTH)
        @subject_ypos = prev_subject_ypos
        @num_objects = prev_num_objects
      end

      def generate_rdf_type(rdf_type)
        add_to_svg(
            predicate_arrow_elements(predicate_arrow_position, :rdf_type, 'rdf:type')
        )

        position = Point.new(@current_pos.x + PREDICATE_AREA_WIDTH, @current_pos.y)
        add_to_svg(uri_elements(position, rdf_type, :class))

        @num_objects += 1
        move_to_next_object
      end

      def generate_predicate(predicate)
        arrow_type = predicate.rdf_type? ? :rdf_type : :predicate
        add_to_svg(
            predicate_arrow_elements(predicate_arrow_position, arrow_type, predicate.uri)
        )
      end

      def generate_object(object)
        pos = Point.new(@current_pos.x + PREDICATE_AREA_WIDTH, @current_pos.y)
        inner_texts = [object.name, object.value]

        case object
        when Model::Unknown
          add_to_svg(unknown_object_elements(pos, inner_texts[0]))
        when Model::URI
          add_to_svg(uri_elements(pos, inner_texts))
        when Model::Literal
          add_to_svg(object_literal_elements(pos, inner_texts, object.data_type))
        end

        @object_pos[object.name] = pos.dup
        @object_positions << pos.dup
        @num_objects += 1
        move_to_next_object
      end

      def generate_blank_node(subject, predicate, properties)
        prev_pos = @current_pos.dup
        prev_subject_ypos = @subject_ypos.dup
        prev_num_objects = @num_objects.dup

        # Draw an arrow pointing to a blank node circle
        add_to_svg(
            predicate_arrow_elements(predicate_arrow_position(:bnode), :predicate, predicate.uri)
        )

        # Draw blank node object (Circle)
        pos = Point.new(@current_pos.x + PREDICATE_AREA_WIDTH, @current_pos.y)
        add_to_svg(blank_node_elements(pos))

        # Draw predicates and objects when the blank node is subject.
        @num_objects = 0
        @current_pos.x = pos.x + BNODE_RADIUS * 2
        @current_pos.y = pos.y
        @subject_ypos = @current_pos.y
        properties.each do |property_hash|
          generate_property(subject, property_hash)
        end

        @current_pos = prev_pos
        @num_objects.times { move_to_next_object }
        @subject_ypos = prev_subject_ypos
        @num_objects = prev_num_objects
      end

      def output_svg
        width = @object_pos.values.map(&:x).max + RECT_WIDTH + 100
        height = @object_pos.values.map(&:y).max + RECT_HEIGHT + MARGIN_RECT + 100
        svg_opts = {
            width: "#{width}px",
            height: "#{height}px",
            viewBox: "-0.5 -0.5 #{width} #{height}"
        }
        @svg_element.add_attribute_by_hash(svg_opts)

        xml = xml_doc
        xml.add_element(@svg_element)
        xml.write($stdout, 2)
      end

      def xml_doc
        doc = REXML::Document.new
        doc.add REXML::XMLDecl.new('1.0', 'UTF-8')
        doc.add REXML::DocType.new('svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"')

        doc
      end

      def add_to_svg(element)
        case element
        when Array
          element.each do |elem|
            @svg_element.add_element(elem)
          end
        else
          @svg_element.add_element(element)
        end
      end

      def subject_config(subject_name)
        @model.yaml.select do |subject_hash|
          name = subject_hash.keys.first.split(/\s+/).first
          name == subject_name
        end.first
      rescue
        {}
      end

      def subject_name?(name)
        /\A[A-Z]/ =~ name
      end

      def predicate_arrow_position(object_type = :not_bnode)
        if object_type == :bnode
          ArrowPosition.new(@current_pos.x, @subject_ypos + RECT_HEIGHT / 2,
                            @current_pos.x + PREDICATE_AREA_WIDTH, @current_pos.y + BNODE_RADIUS)
        else
          ArrowPosition.new(@current_pos.x, @subject_ypos + RECT_HEIGHT / 2,
                            @current_pos.x + PREDICATE_AREA_WIDTH, @current_pos.y + RECT_HEIGHT / 2)
        end
      end

      def style_value_by_hash(hash)
        hash.map { |name, value| "#{name}: #{value}" }.join('; ')
      end

      def bnode_key(predicate_paths)
        predicate_paths[0..-2].join(' / ')
      end

      def move_to_predicate
        @current_pos.x += RECT_WIDTH
      end

      def move_to_next_object
        @current_pos.y += RECT_HEIGHT + MARGIN_RECT
        if @num_objects == YPOS_CHANGE_NUM_OBJ
          @current_pos.x -= RECT_WIDTH / 4
          @subject_ypos += RECT_HEIGHT / 2
        elsif @num_objects == YPOS_CHANGE_NUM_OBJ * 2 - 2
          @current_pos.x -= RECT_WIDTH / 2
        end
      end

      def distance(x1, y1, x2, y2)
        dx = (x2 - x1).abs.to_f
        dy = (y2 - y1).abs.to_f

        Math.sqrt(dx**2 + dy**2)
      end
    end

  end
end

require 'rexml/document'
require 'rdf-config/schema/chart/constant'
require 'rdf-config/schema/chart/subject_generator'
require 'rdf-config/schema/chart/predicate_generator'
require 'rdf-config/schema/chart/loop_predicate_generator'
require 'rdf-config/schema/chart/class_node_generator'
require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/literal_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'
require 'rdf-config/schema/chart/unknown_node_generator'

class REXML::Element
  def add_attribute_by_hash(attr_hash)
    attr_hash.each do |name, value|
      add_attribute(name.to_s, value)
    end
  end
end

class RDFConfig
  class Schema
    class Chart
      include Constant

      Position = Struct.new(:x, :y)
      ArrowPosition = Struct.new(:x1, :y1, :x2, :y2)

      START_X = 50.freeze
      START_Y = 10.freeze

      def initialize(config)
        @model = Model.new(config)
        @prefix = config.prefix

        generate_svg_element
        add_to_svg(style_element)

        @current_pos = Position.new(START_X, START_Y)
        @subjects = []
        @generated_subjects = []
        @element_pos = {}
      end

      def generate
        @model.subjects.each do |subject|
          generate_subject_graph(subject)
        end

        output_svg
      end

      def output_svg
        width = @element_pos.values.flatten.map(&:x).max + RECT_WIDTH + 100
        height = @element_pos.values.flatten.map(&:y).max + RECT_HEIGHT + MARGIN_RECT + 100
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

      def generate_subject_graph(subject)
        return if subject_graph_generated?(subject.name) && @subjects.empty?

        generate_subject(subject)
        if subject_graph_generated?(subject.name)
          @subjects.pop
          return
        end

        subject.predicates.each do |predicate|
          predicate.objects.each do |object|
            generate_predicate_object(predicate, object)
          end
        end

        add_subject(subject.name) unless subject.blank_node?
        @subjects.pop
      end

      def generate_subject(subject)
        unless @element_pos.key?(subject.object_id)
          @element_pos[subject.object_id] = []
        end

        move_to_subject
        @subjects.push(subject)
        add_element_position

        generator = SubjectGenerator.new(subject, @current_pos)
        add_to_svg(generator.generate)
      end

      def generate_predicate_object(predicate, object)
        if loop_to_subject?(object)
          @current_pos.y = @element_pos[object.object_id].last.y + (RECT_HEIGHT + MARGIN_RECT)
        end

        value = predicate.rdf_type? ? object.name : object.value

        case value
        when Array
          value.each do |object_value|
            generate_predicate_object(predicate, object_value)
          end
        else
          move_to_predicate
          generate_predicate(predicate, loop_to_subject?(object))

          # move object position after generating predicate
          @current_pos.x += PREDICATE_AREA_WIDTH
          generate_object(predicate, object)
        end

        #move_to_next_object unless loop_to_subject?(object)
        move_to_next_object
      end

      def generate_predicate(predicate, loop = false)
        predicate_generator = if loop
                                LoopPredicateGenerator.new(predicate, predicate_arrow_position)
                              else
                                PredicateGenerator.new(predicate, predicate_arrow_position)
                              end

        add_to_svg(predicate_generator.generate)
      end

      def generate_object(predicate, object)
        add_element_position

        if object.is_a?(Model::Subject)
          if draw_predicate_object?(object)
            generate_subject_graph(object)
          elsif !loop_to_subject?(object)
            generate_subject(object)
            @subjects.pop
          end
        elsif object.blank_node?
          generate_subject_graph(object.value)
        elsif predicate.rdf_type?
          generator = ClassNodeGenerator.new(object, @current_pos)
          add_to_svg(generator.generate)
        else
          case object
          when Model::Unknown
            generator = UnknownNodeGenerator.new(object, @current_pos)
          when Model::URI
            generator = URINodeGenerator.new(object, @current_pos)
          when Model::Literal
            generator = LiteralNodeGenerator.new(object, @current_pos)
          end

          add_to_svg(generator.generate) if generator
        end
      end

      def draw_predicate_object?(object)
        !@subjects.map(&:name).include?(object.name)
      end

      def subject_position(subject)
        @element_pos[subject.object_id].first
      end

      def move_to_predicate
        @current_pos.x = if current_subject.blank_node?
                           subject_position(current_subject).x + BNODE_RADIUS * 2
                         else
                           subject_position(current_subject).x + RECT_WIDTH
                         end
      end

      def predicate_arrow_position
        y1 = subject_position(current_subject).y + RECT_HEIGHT / 2
        y2 = @current_pos.y + RECT_HEIGHT / 2

        ArrowPosition.new(@current_pos.x, y1,
                          @current_pos.x + PREDICATE_AREA_WIDTH, y2)
      end

      def loop_to_subject?(object)
        #current_subject == object
        false
      end

      def move_to_subject
        @current_pos.x = START_X if @subjects.empty?
      end

      def move_to_next_object
        @current_pos.y = @element_pos.values.flatten.map(&:y).max + RECT_HEIGHT + MARGIN_RECT
      end

      def current_subject
        @subjects.last
      end

      def num_objects
        # notice @element_pos include subject position
        @element_pos[current_subject.object_id].size - 1
      end

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

      def style_element
        style = REXML::Element.new('style')
        style.add_attribute('type', 'text/css')
        style.add_text(<<-STYLE)
	.st0 {fill:#FFCE9F;}
	.st1 {fill:none;stroke:#000000;stroke-width:2;}
	.st2 {opacity:0.6;}
	.st3 {font-family:'Helvetica';}
	.st4 {font-size:11px;}
	.st5 {fill:#FFFFFF;}
	.st6 {font-family:'Helvetica-Bold';}
	.st7 {font-size:12px;}
	.st8 {opacity:0.7;fill:#FFFFFF;}
	.st9 {fill:#F8CECC;stroke:#000000;stroke-width:2;}
	.st10 {fill:#FFF4C3;}
	.st11 {fill:none;stroke:#000000;stroke-width:2;stroke-miterlimit:10;stroke-dasharray:4,4;}
	.st12 {fill:none;stroke:#000000;stroke-width:2;stroke-miterlimit:10;}
	.st13 {enable-background:new;}
	.st14 {fill:#F2F2E9;}
	.st15 {fill:none;stroke:#000000;stroke-width:2;stroke-dasharray:3.926,3.926;}
        STYLE

        style
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

      def add_subject(subject)
        @generated_subjects << subject
      end

      def subject_graph_generated?(subject_name)
        @generated_subjects.include?(subject_name)
      end

      def add_element_position
        @element_pos[current_subject.object_id] << @current_pos.dup
      end

      def distance(x1, y1, x2, y2)
        dx = (x2 - x1).abs.to_f
        dy = (y2 - y1).abs.to_f

        Math.sqrt(dx**2 + dy**2)
      end
    end

  end
end

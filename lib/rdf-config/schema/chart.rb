require 'rexml/document'
require 'rdf-config/schema/chart/constant'
require 'rdf-config/schema/chart/title_generator'
require 'rdf-config/schema/chart/subject_generator'
require 'rdf-config/schema/chart/predicate_generator'
require 'rdf-config/schema/chart/loop_predicate_generator'
require 'rdf-config/schema/chart/class_node_generator'
require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/literal_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'
require 'rdf-config/schema/chart/unknown_node_generator'
require 'rdf-config/schema/chart/prefix_generator'

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
      class SchemaConfigNotFound < StandardError; end
      class InvalidSchemaOption < StandardError; end

      include Constant

      Position = Struct.new(:x, :y)
      ArrowPosition = Struct.new(:x1, :y1, :x2, :y2)

      START_X = 50.freeze
      START_Y = 10.freeze

      def initialize(config, opts = {})
        @config = config
        @model = Model.new(config)
        @prefix = config.prefix
        @opts = opts

        interpret_opt(opts[:schema_opt].to_s) if opts.key?(:schema_opt)

        @current_pos = Position.new(START_X, START_Y)
        @subjects = []
        @generated_subjects = []
        @element_pos = {}
      end

      def generate
        generate_svg_element
        add_to_svg(style_element)

        # Display the title in the upper left
        generate_title

        # Display schema chart
        generate_schema

        # Display the prefixes at the bottom left
        generate_prefixes

        output_svg
      end

      def generate_title
        if !@schema_name.nil? && @config.schema[@schema_name].key?('description')
          description = @config.schema[@schema_name]['description']
          generator = TitleGenerator.new(description, @current_pos)
          add_to_svg(generator.generate)
          @current_pos.y += TITLE_FONT_SIZE[0 .. 3].to_i * 2
        end
      end

      def generate_schema
        if variables.empty?
          generate_all
        else
          generate_by_variables
        end
      end

      def generate_prefixes
        @prefix_generator = PrefixGenerator.new(@prefix, Position.new(START_X, max_ypos))
        add_to_svg(@prefix_generator.generate)
      end

      def generate_all
        @model.subjects.each do |subject|
          generate_subject_graph(subject)
        end
      end

      def generate_by_variables
        @schema_subject_names = []
        @schema_object_names = {}
        variables.each do |variable_name|
          if @model.subject?(variable_name)
            unless @schema_subject_names.include?(variable_name)
              @schema_subject_names << variable_name
              @schema_object_names[variable_name] = []
              subject = @model.find_subject(variable_name)
              subject.predicates.each do |predicate|
                next if predicate.rdf_type?

                predicate.objects.each do |object|
                  case object
                  when Model::Subject
                    object_name = object.as_object_name
                  else
                    object_name = object.name
                  end
                  @schema_object_names[variable_name] << object_name unless @schema_object_names[variable_name].include?(object_name)
                end
              end
            end
          else
            triple = @model.find_by_object_name(variable_name)
            next if triple.nil?

            unless @schema_subject_names.include?(triple.subject.name)
              @schema_subject_names << triple.subject.name
              @schema_object_names[triple.subject.name] = []
            end

            unless @schema_object_names[triple.subject.name].include?(variable_name)
              @schema_object_names[triple.subject.name] << variable_name
            end
          end
        end

        @schema_subject_names.each do |subject_name|
          subject = @model.find_subject(subject_name)
          generate_subject_graph(subject)
        end
      end

      def output_svg
        width = max_xpos + 100
        height = max_ypos + @prefix_generator.height + START_Y
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
            if variables.empty?
              generate_predicate_object(predicate, object)
            else
              next unless @schema_subject_names.include?(subject.name)

              object_name = if object.is_a?(Model::Subject)
                              object.as_object_name
                            else
                              object.name
                            end
              if predicate.rdf_type? || @schema_object_names[subject.name].include?(object_name)
                generate_predicate_object(predicate, object)
              end
            end
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

        disp_mode = if @subjects.size > 1 && @nest
                      :object
                    else
                      :subject
                    end
        generator = SubjectGenerator.new(subject, @current_pos, disp_mode: disp_mode)
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
        if @nest
          !@subjects.map(&:name).include?(object.name)
        else
          false
        end
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

      private

      def interpret_opt(schema_opt)
        errors = []
        valid_options = %w[nest arc table]
        table_types = %w[arc table]

        @schema_name = nil
        @nest = false
        @display_type = :tree # :tree | :arc | :table
        @display_title = true
        @display_prefix = true

        option_names = schema_opt.strip.split(/\s*:\s*/)
        return if option_names.empty?

        schema_name = option_names.shift
        unless schema_name.empty?
          if @config.schema.key?(schema_name)
            @schema_name = schema_name
          else
            errors << "Schema name '#{schema_name}' is specified but not found in schema.yaml file."
          end
        end

        if (table_types & option_names).size == table_types.size
          errors << "Both 'arc' option and 'table' option cannot be specified."
        end

        option_names.each do |name|
          next if name.empty?

          if valid_options.include?(name)
            @nest = true if name == 'nest'
            @display_type = name.to_sym if table_types.include?(name)
            @display_title = false if name == 'no_title'
            @display_prefix = false if name == 'no_prefix'
          else
            errors << "Invalid option '#{name}' is specified."
          end
        end

        unless errors.empty?
          error_msg = "ERROR:\n#{errors.map { |msg| "  #{msg}" }.join("\n")}"
          raise InvalidSchemaOption, error_msg
        end
      end

      def variables
        @variables ||= interpret_variables
      end

      def interpret_variables
        if !@schema_name.nil? && @config.schema[@schema_name].key?('variables')
          vars = @config.schema[@schema_name]['variables'].clone
          @config.schema[@schema_name]['variables'].each do |variable_name|
            next if @model.subject?(variable_name)

            triple = @model.find_by_object_name(variable_name)
            if vars.include?(triple.subject.name)
              vars.delete(triple.subject.name)
            end
          end
          vars
        else
          []
        end
      end

      def max_xpos
        @element_pos.values.flatten.map(&:x).max + RECT_WIDTH
      end

      def max_ypos
        @element_pos.values.flatten.map(&:y).max + RECT_HEIGHT + MARGIN_RECT
      end
    end
  end
end

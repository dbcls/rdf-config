require 'rdf-config/sparql'

class RDFConfig
  class SPARQL
    class WhereGenerator < SPARQL
      PROPERTY_PATH_SEP = ' / '.freeze

      def initialize(config, opts = {})
        super

        @output_values_line = if opts.key?(:output_values_line) && opts[:output_values_line] == false
                                false
                              else
                                true
                              end

        @indent_text = if opts.key?(:indent_text)
                         opts[:indent_text]
                       else
                         ' ' * 4
                       end

        init_instance_variables
      end

      def triples
        variables_handler.visible_variables
      end

      def generate
        lines = []
        @configs.each do |config|
          @config = config
          lines += generate_by_config
        end

        lines = ['WHERE {'] + values_lines + lines
        lines += filter_lines_for_join if join?
        lines << '}'

        lines
      end

      def optional_phrase?(predicate_in_model)
        cardinality = predicate_in_model.cardinality
        cardinality.is_a?(RDFConfig::Model::Cardinality) && (cardinality.min.nil? || cardinality.min.zero?)
      end

      private

      def init_instance_variables
        @values_lines = []
        @required_triples = []
        @optional_triples = []

        @variable = {}
        @blank_nodes = []

        @bnode_number = 1
        @depth = 1

        @target_triple = nil
        @optional_triples_buf = []
      end

      def generate_by_config
        init_instance_variables
        generate_triples
        add_values_lines if @output_values_line

        required_lines + optional_lines
      end

      def generate_triples
        variables_handler.visible_variables.each do |variable_name|
          generate_triple_by_variable(variable_name)
          unless @optional_triples_buf.empty?
            @optional_triples << @optional_triples_buf.uniq
            @optional_triples_buf = []
          end
        end

        @required_triples.uniq!
      end

      def generate_triple_by_variable(variable_name)
        @target_triple = model.find_by_object_name(variable_name)
        return if @target_triple.nil? || @target_triple.subject.name == variable_name

        if @target_triple.bnode_connecting? && model.same_property_path_exist?(variable_name)
          generate_triples_with_bnode
        else
          generate_triple_without_bnode
        end
      end

      def generate_triple_without_bnode
        object_name = @target_triple.object_name
        is_optional = optional?(object_name)

        if model.same_property_path_exist?(object_name)
          triple_in_model = model.find_by_object_name(object_name)
          subject = model.subjects.first
          property_paths = model.property_path(triple_in_model.subject.name)

          # If there is the same property path, it is necessary to output the rdf:type of the subject
          # in which the object is hanging in order to distinguish the target object.
          add_triple(Triple.new(subject_instance(subject, subject.types, true),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(triple_in_model.subject.name)),
                     is_optional)
          add_triple(Triple.new(subject_instance(triple_in_model.subject, triple_in_model.subject.types, true),
                                model.property_path(object_name, @target_triple.subject.name).join(PROPERTY_PATH_SEP),
                                variable_instance(object_name(@target_triple))),
                     is_optional)
        else
          subject = subject_by_object_name(object_name)
          property_paths = model.property_path(object_name, subject.name)
          add_triple(Triple.new(subject_instance(subject, subject.types),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(object_name(@target_triple))),
                     is_optional)
        end
      end

      def predicate_uri
        predicate = @target_triple.predicates.first
        if @target_triple.subject == @target_triple.object && !predicate.rdf_type?
          "#{predicate.uri}*"
        else
          predicate.uri
        end
      end

      def generate_triples_with_bnode
        object_name = @target_triple.object_name
        bnode_rdf_types = model.bnode_rdf_types(@target_triple)

        if use_property_path?(bnode_rdf_types)
          subject = subject_by_object_name(object_name)
          return unless variables_for_where.include?(subject.name)

          property_paths = model.property_path(object_name, subject.name)
          add_triple(Triple.new(subject_instance(subject, subject.types),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(object_name(@target_triple))),
                     optional?(object_name, subject.name))
        else
          generate_triples_with_bnode_rdf_types(bnode_rdf_types)
        end
      end

      def generate_triples_with_bnode_rdf_types(bnode_rdf_types)
        subject_name = @target_triple.subject.name
        parent_subject_names = model.parent_subject_names(subject_name)
        start_subject_name = nil
        parent_subject_names.reverse.each do |parent_subject_name|
          if variables.include?(parent_subject_name)
            start_subject_name = parent_subject_name
            break
          end
        end

        start_subject = if start_subject_name.nil?
                          model.subjects.first
                        else
                          model.find_subject(start_subject_name)
                        end

        add_triple(Triple.new(subject_instance(model.find_subject(start_subject.name), start_subject.types),
                              model.property_path(subject_name, start_subject.name).join(PROPERTY_PATH_SEP),
                              variable_instance(subject_name)),
                   false)

        subject = subject_instance(@target_triple.subject, @target_triple.subject.types)
        predicates = @target_triple.predicates

        bnode_predicates = []
        (0...predicates.size - 1).each do |i|
          bnode_predicates << predicates[i]
          rdf_types = bnode_rdf_types[i]
          next if rdf_types.nil?

          object = blank_node(predicates[0..i].map(&:uri), bnode_rdf_types[i])
          add_triple(Triple.new(subject,
                                bnode_predicates.map(&:uri).join(PROPERTY_PATH_SEP),
                                object),
                     false)
          bnode_predicates.clear
          subject = object
          subject.rdf_types = bnode_rdf_types[i]
        end

        object = variable_instance(@target_triple.object_name)
        add_triple(Triple.new(subject,
                              (bnode_predicates + [predicates.last]).map(&:uri).join(PROPERTY_PATH_SEP),
                              object),
                   optional_phrase?(predicates.last))
      end

      def add_values_lines
        add_values_lines_by_parameters
        add_values_lines_for_rdf_type
      end

      def add_values_lines_by_parameters
        parameters.merge(@values).each do |variable_name, value|
          object = model.find_object(variable_name)
          if object.nil?
            subject = model.find_subject(variable_name)
            next if subject.nil?
          end

          value = "{{#{variable_name}}}" if template?
          value = %("#{value}") if double_quote_value?(object)

          add_values_line(values_line("?#{variable_name}", value))
        end
      end

      def double_quote_value?(object)
        (object.is_a?(RDFConfig::Model::Literal) && !object.value.is_a?(TrueClass) && !object.value.is_a?(FalseClass)) &&
          !object.has_lang_tag? && !object.has_data_type?
      end

      def add_values_lines_for_rdf_type
        all_triples.reject(&:nil?).map(&:subject).uniq.each do |subject|
          next unless subject.has_multiple_rdf_types?

          add_values_line(values_line(subject.rdf_type_varname, subject.rdf_types.join(' ')))
        end
      end

      def required_lines
        lines = []

        [Variable, BlankNode].each do |subject_class|
          sort_triples(@required_triples).map(&:subject).select do |subject|
            subject.is_a?(subject_class)
          end.uniq.each do |subject|
            case subject
            when Variable
              triples = filter_triples_by_subject(subject)
              lines += lines_by_subject(subject) unless triples.empty?
            else
              lines += lines_by_subject(subject)
            end
          end
        end

        lines
      end

      def filter_triples_by_subject(subject)
        subject_names = @required_triples.map(&:subject).select do |subject|
          subject.is_a?(Variable)
        end.map(&:name).uniq

        @required_triples.select do |triple|
          triple.subject.name == subject.name && (
            variables.include?(triple.subject.name) || (
              !triple.rdf_type? && !subject_names.include?(triple.object.name)
            )
          )
        end
      end

      def lines_by_subject(subject)
        return [] if subject.is_a?(RDFConfig::SPARQL::WhereGenerator::BlankNode)

        triples = @required_triples.select { |triple| triple.subject == subject }
        return [] if triples.empty?

        lines = lines_by_triples(triples)
        if lines.size.positive? && lines.last[-1] == ';'
          line = lines.pop
          lines << line.gsub(/;\z/, '.')
        end

        lines
      end

      def lines_by_triples(triples, depth_indent = 0)
        lines = []
        return lines if triples.size.zero?

        if triples.first.subject.is_a?(RDFConfig::SPARQL::WhereGenerator::BlankNode)
          triples.each do |triple|
            line = triple.to_sparql(indent: indent,
                                    is_first_triple: false,
                                    is_last_triple: false,
                                    variable_name_prefix: join? ? "#{config_name}__" : '')
            if line =~ /(_:b\d+)/
              subject_name = $1
              lines << "#{indent(depth_indent)}#{line.gsub(/_:b\d+.*/, '[')}"
              object_triples = @required_triples.select { |t| t.subject.to_sparql == subject_name }
              lines += lines_by_triples(object_triples, depth_indent + 1)
            else
              lines << "#{indent(depth_indent)}#{line}"
            end
          end
          lines << "#{indent(depth_indent + 1)}] ;"
        else
          triples.each do |triple|
            line = triple.to_sparql(indent: indent,
                                    is_first_triple: triple.object == triples.first.object,
                                    is_last_triple: triple.object == triples.last.object,
                                    variable_name_prefix: join? ? "#{config_name}__" : '')
            if line =~ /(_:b\d+)/
              subject_name = $1
              lines << line.gsub(/_:b\d+.*/, '[')
              object_triples = @required_triples.select { |t| t.subject.to_sparql == subject_name }
              lines += lines_by_triples(object_triples, depth_indent)
            else
              lines << line
            end
          end
        end

        lines
      end

      def optional_lines
        lines = []

        @optional_triples.each do |optional_triples|
          next if optional_triples.empty?

          optional_triples.reject! { |triple| @required_triples.include?(triple) }
          lines += generate_optional_lines(sort_triples(optional_triples))
        end

        lines
      end

      def generate_optional_lines(optional_triples)
        return [] if optional_triples.empty?

        left_indent = @indent_text
        lines = ["#{left_indent}OPTIONAL {"]
        subject_names = optional_triples.map(&:subject).map(&:name).uniq
        subject_names.each do |subject_name|
          triples = optional_triples.select { |triple| triple.subject.name == subject_name }
          triples.each do |triple|
            lines << triple.to_sparql(indent: @indent_text,
                                      is_first_triple: triple.object == triples.first.object,
                                      is_last_triple: triple.object == triples.last.object,
                                      left_indent: left_indent,
                                      variable_name_prefix: join? ? "#{config_name}__" : '')
          end
        end
        lines << "#{left_indent}}"

        lines
      end

      def values_lines
        @values_lines.uniq
      end

      def values_line(variavale_name, value)
        "#{@indent_text}VALUES #{variavale_name} { #{value} }"
      end

      def use_property_path?(bnode_rdf_types)
        flatten = bnode_rdf_types.flatten
        flatten.uniq.size == 1 && flatten.first.nil?
      end

      def add_triple(triple, is_optional)
        return if triple.predicate.strip.to_s.size.zero? || triple.subject.name == triple.object.name

        case triple
        when Array
          triple.each do |t|
            add_triple(t, is_optional)
          end
        else
          more_triples = []
          triple_for_subject_rdf_type = if triple.subject.has_rdf_type?
                                          Triple.new(triple.subject, 'a', triple.subject)
                                        end

          if model.subject?(triple.object.name)
            object = model.find_subject(triple.object.name)
            subject = subject_instance(object, object.types, true)
            triple_for_object_rdf_type = Triple.new(subject, 'a', subject)
          else
            object = model.find_object(triple.object.name)
            if object.is_a?(Model::Subject)
              subject = subject_instance(object, object.types)
              triple_for_object_rdf_type = Triple.new(subject, 'a', subject)
              (variables & object.object_names).each do |variable_name|
                next if variable_name == object.as_object_name

                triple_in_model = model.find_by_object_name(variable_name)
                next if triple_in_model.nil?

                more_triples << Triple.new(subject_instance(object, triple_in_model.subject.types),
                                           model.property_path(variable_name,
                                                               object.as_object_value).join(PROPERTY_PATH_SEP),
                                           variable_instance(variable_name))
              end
            else
              triple_for_object_rdf_type = nil
            end
          end

          if is_optional
            if triple_for_subject_rdf_type && !@optional_triples_buf.include?(triple_for_subject_rdf_type)
              @optional_triples_buf << triple_for_subject_rdf_type
            end
            if !triple_for_object_rdf_type.nil? && !@optional_triples_buf.include?(triple_for_object_rdf_type)
              @optional_triples_buf << triple_for_object_rdf_type
            end
            @optional_triples_buf << triple unless @optional_triples_buf.include?(triple)
            more_triples.each do |triple|
              @optional_triples_buf << triple unless @optional_triples_buf.include?(triple)
            end
          else
            if triple_for_subject_rdf_type && !@required_triples.include?(triple_for_subject_rdf_type)
              @required_triples << triple_for_subject_rdf_type
            end
            if !triple_for_object_rdf_type.nil? && !@required_triples.include?(triple_for_object_rdf_type)
              @required_triples << triple_for_object_rdf_type
            end
            @required_triples << triple unless @required_triples.include?(triple)
            more_triples.each do |triple|
              @required_triples << triple unless @required_triples.include?(triple)
            end
          end
        end
      end

      def subject_instance(subject, rdf_types = nil, use_subject_name = false)
        if subject.is_a?(Array)
          rdf_types = subject
          subject = @target_triple.subject
        end

        if subject.blank_node? && subject.types.size > 1
          blank_node([], subject.types)
        else
          if use_subject_name
            v_inst = variable_instance(subject.name)
          else
            triple = if subject.used_as_object?
                       model.find_by_object_name(subject.as_object_name)
                     else
                       model.find_by_object_name(subject.name)
                     end
            v_inst = if triple.nil?
                       variable_instance(subject.name)
                     else
                       variable_instance(object_name(triple))
                     end
          end
          v_inst.rdf_types = rdf_types unless rdf_types.nil?

          v_inst
        end
      end

      def variable_instance(variable_name)
        if @variable.key?(variable_name)
          @variable[variable_name]
        else
          add_variable(variable_name)
        end
      end

      def add_variable(variable_name)
        @variable[variable_name] = Variable.new(
          variable_name, sparql_variable_name: variable_name_for_sparql(variable_name, true)
        )
      end

      def blank_node(predicate_routes, rdf_types)
        bnodes = @blank_nodes.select do |bnode|
          bnode.predicate_routes == predicate_routes && bnode.rdf_types == rdf_types
        end

        if bnodes.empty?
          add_blank_node(predicate_routes, rdf_types)
        else
          bnodes.first
        end
      end

      def add_blank_node(predicate_routes, rdf_types)
        bnode = BlankNode.new(@bnode_number, predicate_routes)
        bnode.rdf_types = rdf_types
        @blank_nodes << bnode
        @bnode_number += 1

        bnode
      end

      def add_values_line(line)
        @values_lines << line
      end

      def all_triples
        @required_triples + @optional_triples.flatten
      end

      def template?
        @opts.key?(:template) && @opts[:template] == true
      end

      def indent(depth_increment = 0)
        (@indent_text * (@depth + depth_increment)).to_s
      end

      def optional?(object_name, start_subject = nil)
        model.predicate_path(object_name, start_subject).reject(&:required?).size.positive?
      end

      def object_name(triple)
        case triple.object
        when Model::Subject
          if variables.include?(triple.object.as_object_name)
            triple.object.as_object_name
          else
            triple.object.as_object_value
          end
        when Model::ValueList
          names = variables & triple.object.value.select { |v| v.is_a?(Model::Subject) }.map(&:as_object_name)
          if names.empty?
            names = variables & triple.object.value.select { |v| v.is_a?(Model::Subject) }.map(&:as_object_value)
            if names.empty?
              triple.object.name
            else
              names.first
            end
          else
            names.first
          end
        else
          triple.object.name
        end
      end

      def sort_triples(triples)
        subject_names = model.subject_names
        triples.sort do |t1, t2|
          if model.subject?(t1.subject.name) && model.subject?(t2.subject.name)
            subject_names.index(t1.subject.name) <=> subject_names.index(t2.subject.name)
          elsif model.subject?(t1.subject.name)
            # t2.object is not subject, pure object
            triple = model.find_by_object_name(t2.object.name)
            if triple.nil?
              0
            else
              if t1.subject.name == triple.subject.name
                -1
              else
                subject_names.index(t1.subject.name) <=> subject_names.index(triple.subject.name)
              end
            end
          elsif model.subject?(t2.subject.name)
            # t1.object is not subject, pure object
            triple = model.find_by_object_name(t1.object.name)
            if triple.nil?
              0
            else
              if triple.subject.name == t2.subject.name
                1
              else
                subject_names.index(triple.subject.name) <=> subject_names.index(t2.subject.name)
              end
            end
          else
            # both t1.object and t2.object is not subject, pure object
            0
          end
        end
      end

      def filter_lines_for_join
        lines = []
        @opts[:join].each do |join|
          left, right = join.split('=')
          lines <<
            "#{@indent_text}FILTER(?#{left.gsub(':', '__')} = ?#{right.gsub(':', '__')})"
        end

        lines
      end
    end
  end
end

require 'rdf-config/sparql/where_generator/triple'
require 'rdf-config/sparql/where_generator/rdf_type'
require 'rdf-config/sparql/where_generator/variable'
require 'rdf-config/sparql/where_generator/blank_node'

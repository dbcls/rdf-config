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

      private

      def init_instance_variables
        @values_lines = []
        @rdf_type_triple = {}
        @object_rdf_type_triples = []
        @required_triples = []
        @optional_triples = []
        @bnode_subject_triples = []

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

        refine_triples
      end

      def refine_triples
        refine_rdf_type_triple
        refine_required_triple
        refine_bnode_subject_triple
        refine_optional_triple
      end

      def refine_rdf_type_triple; end

      def refine_required_triple; end

      def refine_optional_triple
        @optional_triples.reject!(&:empty?)
        @optional_triples = @optional_triples.map(&:uniq)
      end

      def refine_bnode_subject_triple
        @bnode_subject_triples.uniq!(&:to_s)

        refined_triples = []
        @bnode_subject_triples.each do |triple|
          if @rdf_type_triple.key?(triple.subject.name)
            refined_triples << @rdf_type_triple.delete(triple.subject.name)
            add_values_line_for_rdf_type(triple.subject)
          end
          refined_triples << triple
        end

        @bnode_subject_triples = refined_triples
      end

      def rdf_type_added_triples(triples, required: true)
        refined_triples = []
        triples.each do |triple|
          orig_triple_is_added = false

          # Subject rdf:type
          if @rdf_type_triple.key?(triple.subject.name) && !triple.subject.instance_of?(BlankNode)
            rdf_type_triple = @rdf_type_triple[triple.subject.name]
            refined_triples << rdf_type_triple
            @rdf_type_triple.delete(triple.subject.name) if required
            refined_triples << triple
            orig_triple_is_added = true
            add_values_line_for_rdf_type(triple.subject)
          end

          # Object rdf:type
          if @rdf_type_triple.key?(triple.object.name) &&
             !triple.object.instance_of?(BlankNode) &&
             !subject_names_by_triples(@required_triples).include?(triple.object.name)
            unless orig_triple_is_added
              refined_triples << triple
              orig_triple_is_added = true
            end

            rdf_type_triple = @rdf_type_triple[triple.object.name]
            if required
              @object_rdf_type_triples << rdf_type_triple
              # refined_triples << rdf_type_triple
              @rdf_type_triple.delete(triple.object.name)
            else
              refined_triples << rdf_type_triple
            end
            add_values_line_for_rdf_type(triple.object)
          end

          refined_triples << triple unless orig_triple_is_added
        end

        refined_triples
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

          # If there is the same property path, it is necessary to output the rdf:type of the subject
          # in which the object is hanging in order to distinguish the target object.
          add_triple(Triple.new(subject_instance(subject, subject.types, true),
                                model.predicate_path(triple_in_model.subject.name),
                                variable_instance(triple_in_model.subject.name)),
                     is_optional)

          use_subject_name = true
          add_triple(Triple.new(subject_instance(triple_in_model.subject, triple_in_model.subject.types, use_subject_name),
                                model.predicate_path(object_name, @target_triple.subject.name),
                                variable_instance(object_name(@target_triple))),
                     is_optional)
        else
          subject = subject_by_object_name(object_name)
          add_triple(Triple.new(subject_instance(subject, subject.types),
                                model.predicate_path(object_name, subject.name),
                                variable_instance(object_name(@target_triple))),
                     is_optional)
        end
      end

      def generate_triples_with_bnode
        object_name = @target_triple.object_name
        bnode_rdf_types = model.bnode_rdf_types(@target_triple)

        if use_property_path?(bnode_rdf_types)
          subject = subject_by_object_name(object_name)
          return unless variables_for_where.include?(subject.name)

          add_triple(Triple.new(subject_instance(subject, subject.types),
                                model.predicate_path(object_name, subject.name),
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
        is_optional = optional?(subject_name, start_subject)
        add_triple(Triple.new(subject_instance(model.find_subject(start_subject.name), start_subject.types),
                              model.predicate_path(subject_name, start_subject.name),
                              variable_instance(subject_name)),
                   is_optional)

        subject = subject_instance(@target_triple.subject, @target_triple.subject.types, true)
        predicates = @target_triple.predicates

        bnode_predicates = []
        (0...predicates.size - 1).each do |i|
          bnode_predicates << predicates[i]
          rdf_types = bnode_rdf_types[i]
          next if rdf_types.nil?

          object = blank_node(predicates[0..i].map(&:uri), bnode_rdf_types[i])
          add_triple(Triple.new(subject,
                                bnode_predicates.dup,
                                object),
                     is_optional)
          bnode_predicates.clear
          subject = object
          subject.rdf_types = bnode_rdf_types[i]
        end

        object = variable_instance(@target_triple.object_name)
        add_triple(Triple.new(subject,
                              (bnode_predicates + [predicates.last]),
                              object),
                   optional?(object.name, subject))
      end

      def add_values_lines
        add_values_lines_by_parameters
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
        (object.is_a?(RDFConfig::Model::Literal) &&
          !object.value.is_a?(Numeric) &&
          !object.value.is_a?(TrueClass) && !object.value.is_a?(FalseClass)) &&
          !object.has_lang_tag? && !object.has_data_type?
      end

      def add_values_line_for_rdf_type(subject)
        return if subject.rdf_types.size < 2

        add_values_line(values_line(subject.rdf_type_varname, subject.rdf_types.join(' ')))
      end

      def required_lines
        lines = []
        [Variable, BlankNode].each do |subject_class|
          @required_triples.map(&:subject).select {|subject| subject.is_a?(subject_class) }.uniq.each do |subject|
            @object_rdf_type_triples.clear

            case subject
            when Variable
              triples = filter_triples_by_subject(subject)
              unless triples.empty?
                triples = sort_triples_by_object(triples)
                triples = rdf_type_added_triples(triples, required: true)
                lines += lines_by_triples(triples)
                if lines.size.positive? && lines.last[-1] == ';'
                  line = lines.pop
                  lines << line.gsub(/;\z/, '.')
                end
              end
              @object_rdf_type_triples.each do |triple|
                lines << triple.to_sparql(indent: indent)
              end
            else
              lines += lines_by_subject(subject)
            end
          end
        end

        lines
      end

      def filter_triples_by_subject(subject)
        subject_names = subject_names_by_triples(@required_triples)
        triples = @required_triples.select do |triple|
          triple.subject.name == subject.name && (
            variables.include?(triple.subject.name) ||
              variables.include?(triple.object.name) ||
              (!triple.rdf_type? && !subject_names.include?(triple.object.name))
          )
        end

        if triples.size == 1 && !variables.include?(triples[0].subject.name) && model.subject?(triples[0].object.name)
          []
        else
          triples
        end
      end

      def subject_names_by_triples(triples)
        triples.map(&:subject).select { |subject| subject.is_a?(Variable) }.map(&:name).uniq
      end

      def lines_by_subject(subject)
        return [] if subject.is_a?(RDFConfig::SPARQL::WhereGenerator::BlankNode)

        triples = @required_triples.select { |triple| triple.subject == subject }
        return [] if triples.empty?

        triples = sort_triples_by_object(triples)
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

        if triples.first.subject.bnode?
          triples.each do |triple|
            line = triple.to_sparql(indent: indent,
                                    is_first_triple: false,
                                    is_last_triple: false,
                                    variable_name_prefix: join? ? "#{config_name}__" : '')
            if line =~ /(_:b\d+)/
              subject_name = $1
              lines << "#{indent(depth_indent)}#{line.gsub(/_:b\d+.*/, '[')}"
              object_triples = @bnode_subject_triples.select { |t| t.subject.to_sparql == subject_name }
              lines += lines_by_triples(object_triples, depth_indent + 1)
            else
              lines << "#{indent(depth_indent)}#{line}"
            end
          end
          lines << "#{indent(depth_indent + 1)}] #{triples.first.subject.bnode? ? ';' : '.'}"
        else
          triples.each do |triple|
            line = triple.to_sparql(indent: indent,
                                    is_first_triple: triple.object == triples.first.object,
                                    is_last_triple: triple.object == triples.last.object,
                                    variable_name_prefix: join? ? "#{config_name}__" : '')
            if line =~ /(_:b\d+)/
              subject_name = $1
              lines << line.gsub(/_:b\d+.*/, '[')
              object_triples = @bnode_subject_triples.select { |t| t.subject.to_sparql == subject_name }
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

        @optional_triples.each do |triples|
          next if triples.empty?

          @object_rdf_type_triples.clear

          triples = rdf_type_added_triples(triples, required: false)
          lines += generate_optional_lines(triples.uniq(&:to_s))
        end

        lines
      end

      def generate_optional_lines(triples)
        return [] if triples.empty?

        left_indent = @indent_text
        lines = ["#{left_indent}OPTIONAL {"]

        subject_names = triples.map(&:subject).map(&:name).uniq
        subject_names.each do |subject_name|
          triples_by_subject = triples.select { |triple| triple.subject.name == subject_name }
          lines += lines_by_triples(triples_by_subject).map { |line| "#{left_indent}#{line}" }
        end

        if lines.last[-1] == ';'
          line = lines.pop
          lines << line.gsub(/;\z/, '.')
        end
        lines << "#{left_indent}}"

        lines
      end

      def values_lines
        sort_values_lines(@values_lines.uniq)
      end

      def values_line(variavale_name, value)
        "#{@indent_text}VALUES #{variavale_name} { #{value} }"
      end

      def use_property_path?(bnode_rdf_types)
        flatten = bnode_rdf_types.flatten
        flatten.uniq.size == 1 && flatten.first.nil?
      end

      def add_triple(triple, is_optional)
        return if triple.predicates.empty? || triple.subject.name == triple.object.name

        case triple
        when Array
          triple.each do |t|
            add_triple(t, is_optional)
          end
        else
          more_triples = []
          triple_for_subject_rdf_type = if triple.subject.has_rdf_type?
                                          Triple.new(triple.subject,
                                                     [Model::Predicate.new('a')],
                                                     triple.subject)
                                        end

          if model.subject?(triple.object.name)
            object = model.find_subject(triple.object.name)
            subject = subject_instance(object, object.types, true)
            triple_for_object_rdf_type = Triple.new(subject,
                                                    [Model::Predicate.new('a')],
                                                    subject)
          else
            object = model.find_object(triple.object.name)
            if object.is_a?(Model::Subject)
              subject = subject_instance(object, object.types)
              triple_for_object_rdf_type = Triple.new(subject,
                                                      [Model::Predicate.new('a')],
                                                      subject)
              (variables & object.object_names).each do |variable_name|
                next if variable_name == object.as_object_name

                triple_in_model = model.find_by_object_name(variable_name)
                next if triple_in_model.nil?

                more_triples << Triple.new(subject_instance(object, triple_in_model.subject.types),
                                           model.predicate_path(variable_name, object.as_object_value),
                                           variable_instance(variable_name))
              end
            else
              triple_for_object_rdf_type = nil
            end
          end

          add_rdf_type_triple(triple_for_subject_rdf_type) if triple_for_subject_rdf_type
          add_rdf_type_triple(triple_for_object_rdf_type) if triple_for_object_rdf_type

          if triple.subject.bnode?
            add_bnode_subject_triples(more_triples.unshift(triple))
          elsif is_optional
            add_optional_triples(more_triples.unshift(triple))
          else
            add_required_triples(more_triples.unshift(triple))
          end
        end
      end

      def add_rdf_type_triple(triple)
        return if triple.subject.rdf_types.empty?

        subject_name = triple.subject.name
        return if @rdf_type_triple.key?(subject_name)

        @rdf_type_triple[subject_name] = triple
      end

      def add_required_triples(triples)
        triples.each do |triple|
          # next if @required_triples.map(&:to_s).include?(triple.to_s)
          next if @required_triples.select { |required_triple| same_triple?(required_triple, triple) }.size.positive?

          @required_triples << triple
        end
      end

      def add_optional_triples(triples)
        triples.each do |triple|
          add_optional_triple(triple)
        end
      end

      def add_optional_triple(triple)
        done_add = false
        @optional_triples.each_with_index do |triples, i|
          next if triples.select { |t| t.subject.to_s == triple.subject.to_s }.empty?

          if triples.map(&:to_s).include?(triple.to_s)
            done_add = true
          elsif triple.required?
            @optional_triples[i] << triple unless triples.map(&:to_s).include?(triple.to_s)
            done_add = true
          end
        end

        return if done_add

        @optional_triples_buf << triple
      end

      def add_bnode_subject_triples(triples)
        triples.each do |triple|
          @bnode_subject_triples << triple
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
        return if @values_lines.include?(line)

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

      def sort_triples_by_subject(triples)
        subject_names = model.subject_names
        triples.sort do |ta, tb|
          if model.subject?(ta.subject.name) && model.subject?(tb.subject.name)
            subject_names.index(ta.subject.name) <=> subject_names.index(tb.subject.name)
          elsif model.subject?(ta.subject.name)
            # t2.object is not subject, pure object
            triple = model.find_by_object_name(tb.object.name)
            if triple.nil?
              0
            else
              if ta.subject.name == triple.subject.name
                -1
              else
                subject_names.index(ta.subject.name) <=> subject_names.index(triple.subject.name)
              end
            end
          elsif model.subject?(tb.subject.name)
            # t1.object is not subject, pure object
            triple = model.find_by_object_name(ta.object.name)
            if triple.nil?
              0
            else
              if triple.subject.name == tb.subject.name
                1
              else
                subject_names.index(triple.subject.name) <=> subject_names.index(tb.subject.name)
              end
            end
          else
            # both t1.object and t2.object is not subject, pure object
            0
          end
        end
      end

      def sort_triples_by_object(triples)
        select_variable_names = select_variables(add_question_mark: false)
        triples.sort do |ta, tb|
          if select_variable_names.include?(ta.object.name) && select_variable_names.include?(tb.object.name)
            select_variable_names.index(ta.object.name) <=> select_variable_names.index(tb.object.name)
          elsif select_variable_names.include?(ta.object.name)
            -1
          elsif select_variable_names.include?(tb.object.name)
            1
          else
            ta.object.name <=> tb.object.name
          end
        end
      end

      def sort_values_lines(values_lines)
        select_variable_names = select_variables(add_question_mark: true)
        values_lines.sort do |lna, lnb|
          lna_parts = lna.strip.split(/\s+/)
          lnb_parts = lnb.strip.split(/\s+/)
          if lna_parts[1].end_with?('__class') && lnb_parts[1].end_with?('__class')
            lna_varname = lna_parts[1][0..-8]
            lnb_varname = lnb_parts[1][0..-8]
            if select_variable_names.include?(lna_varname) && select_variable_names.include?(lnb_varname)
              select_variable_names.index(lna_varname) <=> select_variable_names.index(lnb_varname)
            elsif select_variable_names.include?(lna_varname)
              -1
            elsif select_variable_names.include?(lnb_varname)
              1
            else
              0
            end
          elsif lna_parts[1].end_with?('__class')
            1
          elsif lnb_parts[1].end_with?('__class')
            -1
          else
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

      def same_triple?(triple_a, triple_b)
        return true if triple_a.to_s == triple_b.to_s
        return false if triple_a.property_path != triple_b.property_path

        if triple_a.subject.name != triple_b.subject.name && triple_a.object.name == triple_b.object.name
          if model.subject?(triple_a.subject.name)
            triple_in_model = model.find_by_object_name(triple_b.subject.name)
            !triple_in_model.nil? && triple_a.subject.name == triple_in_model.object.name
          else
            triple_in_model = model.find_by_object_name(triple_a.subject.name)
            !triple_in_model.nil? && triple_b.subject.name == triple_in_model.object.name
          end
          triple_in_model = if model.subject?(triple_a.subject.name)
                              model.find_by_object_name(triple_b.subject.name)
                            else
                              model.find_by_object_name(triple_a.subject.name)
                            end
          !triple_in_model.nil? && [triple_a.subject.name, triple_b.subject.name].include?(triple_in_model.object_name)
        elsif triple_a.subject.name == triple_b.subject.name && triple_a.object.name != triple_b.object.name
          if model.subject?(triple_a.object.name)
            triple_in_model = model.find_by_object_name(triple_b.object.name)
            !triple_in_model.nil? && triple_a.object.name == triple_in_model.object.name
          else
            triple_in_model = model.find_by_object_name(triple_a.object.name)
            !triple_in_model.nil? && triple_b.object.name == triple_in_model.object.name
          end
        else
          false
        end
      end
    end
  end
end

require 'rdf-config/sparql/where_generator/triple'
require 'rdf-config/sparql/where_generator/rdf_type'
require 'rdf-config/sparql/where_generator/variable'
require 'rdf-config/sparql/where_generator/blank_node'

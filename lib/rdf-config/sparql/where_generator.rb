require 'rdf-config/sparql'

class RDFConfig
  class SPARQL
    class WhereGenerator < SPARQL
      @@indent_text = '    '
      PROPERTY_PATH_SEP = ' / '.freeze

      class Triple
        attr_reader :subject, :predicate, :object

        def initialize(subject, predicate, object)
          @subject = subject
          @predicate = predicate

          @object = if object.is_a?(Array) && object.size == 1
                      object.first
                    else
                      object
                    end
        end

        def rdf_type?
          %w[a rdf:type].include?(@predicate)
        end

        def to_sparql(indent = '', is_first_triple = true, is_last_triple = true, left_indent = '')
          line = if is_first_triple
                   "#{left_indent}#{indent}#{subject.to_sparql} "
                 else
                   "#{left_indent}#{indent * 2}"
                 end
          line = if rdf_type?
                   if object.has_one_rdf_type?
                     "#{line}a #{object.rdf_type}"
                   else
                     "#{line}a #{object.rdf_type_varname}"
                   end
                 else
                   "#{line}#{predicate} #{object.to_sparql}"
                 end
          line = "#{line} #{is_last_triple ? '.' : ';'}"

          line
        end

        def ==(other)
          @subject == other.subject && @predicate == other.predicate && @object == other.object
        end
      end

      module RDFType
        def has_rdf_type?
          case rdf_types
          when String
            !rdf_types.strip.empty?
          when Array
            !rdf_types.flatten.uniq.first.nil?
          else
            false
          end
        end

        def has_one_rdf_type?
          has_rdf_type? && (rdf_types.instance_of?(String) || rdf_types.size == 1)
        end

        def has_multiple_rdf_types?
          has_rdf_type? && rdf_types.size > 1
        end

        def rdf_types=(rdf_types)
          @rdf_types = case rdf_types
                       when Array
                         rdf_types
                       when String
                         [rdf_types]
                       end
        end

        def rdf_type
          @rdf_types.first
        end
      end

      class Variable
        include RDFType

        attr_reader :name, :rdf_types

        def initialize(name)
          @name = name
        end

        def to_sparql
          case name
          when Array
            name.to_s
          else
            "?#{name}"
          end
        end

        def rdf_type_varname
          "#{to_sparql}Class"
        end

        def ==(other)
          @name == other.name
        end
      end

      class BlankNode
        include RDFType

        attr_reader :predicate_routes, :rdf_types

        def initialize(bnode_id, predicate_routes)
          @bnode_id = bnode_id
          @predicate_routes = predicate_routes
        end

        def name
          "_b#{@bnode_id}"
        end

        def to_sparql
          "_:b#{@bnode_id}"
        end

        def rdf_type_varname
          "?#{name}Class"
        end

        def ==(other)
          name == other.name
        end
      end

      def initialize(config, opts = {})
        super

        if opts.key?(:output_values_line) && opts[:output_values_line] == false
          @output_values_line = false
        else
          @output_values_line = true
        end

        if opts.key?(:indent_text)
          @@indent_text = opts[:indent_text]
        end

        @values_lines = []
        @required_triples = []
        @optional_triples = []

        @variable = {}
        @blank_nodes = []

        @bnode_number = 1
        @depth = 1

        @target_triple = nil

        prepare_sparql_variable_name
      end

      def generate
        generate_triples
        @required_triples.uniq!
        @optional_triples.uniq!

        add_values_lines if @output_values_line

        lines = required_lines
        lines += optional_lines
        lines = ['WHERE {'] + values_lines + lines
        lines << '}'

        lines
      end

      def optional_phrase?(predicate_in_model)
        cardinality = predicate_in_model.cardinality
        cardinality.is_a?(RDFConfig::Model::Cardinality) && (cardinality.min.nil? || cardinality.min == 0)
      end

      private

      def generate_triples
        variables_for_where.each do |variable_name|
          generate_triple_by_variable(variable_name_for_sparql(variable_name))
        end
      end

      def generate_triple_by_variable(variable_name)
        @target_triple = model.find_by_object_name(variable_name)
        return if @target_triple.nil? || @target_triple.subject.name == variable_name
        return if @target_triple.object.is_a?(Model::ValueList) && !@target_triple.object.value.select { |v| v.is_a?(Model::Subject) }.empty?

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
          add_triple(Triple.new(subject_instance(subject, subject.types, true),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(triple_in_model.subject.name)),
                     is_optional)
          add_triple(Triple.new(subject_instance(triple_in_model.subject, triple_in_model.subject.types, true),
                                model.property_path(object_name, @target_triple.subject.name).join(PROPERTY_PATH_SEP),
                                variable_instance(@target_triple.object.sparql_varname)),
                     is_optional)
        else
          subject = subject_by_object_name(object_name)
          property_paths = model.property_path(object_name, subject.name)
          add_triple(Triple.new(subject_instance(subject, subject.types),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(@target_triple.object.sparql_varname)),
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
          return if !variables_for_where.include?(subject.name)

          property_paths = model.property_path(object_name, subject.name)
          add_triple(Triple.new(subject_instance(subject, subject.types),
                                property_paths.join(PROPERTY_PATH_SEP),
                                variable_instance(@target_triple.object.sparql_varname)),
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

        if start_subject_name.nil?
          start_subject = model.subjects.first
        else
          start_subject = model.find_subject(start_subject_name)
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

      def generate_rdf_type_triples
        triples = rdf_type_triples_by_subjects
        subjects = (@required_triples + @optional_triples).map(&:subject).uniq

        (variables - subjects.map(&:name)).each do |variable_name|
          triple = rdf_type_triple_by_variable(variable_name)
          triples << triple if triple.is_a?(Triple)
        end

        triples
      end

      def rdf_type_triples_by_subjects
        triples = []

        subjects = (@required_triples + @optional_triples).map(&:subject).uniq
        subjects.each do |subject|
          triples << Triple.new(subject, 'a', subject) if subject.has_rdf_type?
        end

        triples
      end

      def rdf_type_triple_by_variable(variable_name)
        triple_in_model = model.find_by_object_name(variable_name)
        return if triple_in_model.nil?

        rdf_type_triple_by_object(triple_in_model.object, variable_name)
      end

      def rdf_type_triple_by_object(object_in_model, variable_name)
        case object_in_model
        when Model::Subject
          rdf_type_triple_by_subject(object_in_model, variable_name)
        when Model::ValueList
          rdf_type_triple_by_value_list(object_in_model.value, variable_name)
        end
      end

      def rdf_type_triple_by_subject(subject_in_model, variable_name)
        if subject_in_model.types.nil?
          nil
        else
          variable = variable_instance(variable_name)
          variable.rdf_types = subject_in_model.types
          Triple.new(variable, 'rdf:type', variable)
        end
      end

      def rdf_type_triple_by_value_list(value_list, variable_name)
        rdf_types = []
        value_list.each do |v|
          next if !v.is_a?(Model::Subject) || v.types.empty?

          rdf_types << v.types
        end

        if rdf_types.empty?
          nil
        else
          variable = variable_instance(variable_name)
          variable.rdf_types = rdf_types.flatten
          Triple.new(variable, 'rdf:type', variable)
        end
      end

      def add_values_lines
        add_values_lines_by_parameters
        add_values_lines_for_rdf_type
      end

      def add_values_lines_by_parameters
        parameters.each do |variable_name, value|
          object = model.find_object(variable_name)
          next if object.nil?

          value = "{{#{variable_name}}}" if template?
          value = %("#{value}") if object.is_a?(RDFConfig::Model::Literal) && !object.has_lang_tag? && !object.has_data_type?

          add_values_line(values_line("?#{variable_name}", value))
        end
      end

      def add_values_lines_for_rdf_type
        all_triples.map(&:subject).uniq.each do |subject|
          next unless subject.has_multiple_rdf_types?

          add_values_line(values_line(subject.rdf_type_varname, subject.rdf_types.join(' ')))
        end
      end

      def required_lines
        lines = []

        [Variable, BlankNode].each do |subject_class|
          @required_triples.map(&:subject).select { |subject| subject.is_a?(subject_class) }.uniq.each do |subject|
            case subject
            when Variable
              triples = filter_triples_by_subject(subject)
              #puts triples.size
              lines += lines_by_subject(subject) unless triples.empty?
            else
              lines += lines_by_subject(subject)
            end
          end
        end

        lines
      end

      def filter_triples_by_subject(subject)
        subject_names = @required_triples.map(&:subject).select do |s|
          s.is_a?(Variable)
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
        lines = []

        triples = @required_triples.select { |triple| triple.subject == subject }
        return [] if triples.empty?

        triples.each do |triple|
          lines << triple.to_sparql(indent,
                                    triple.object == triples.first.object,
                                    triple.object == triples.last.object)
        end

        lines
      end

      def optional_lines
        lines = []

        variables.each do |variable_name|
          next if model.find_by_object_name(variable_name).nil?

          lines += optional_lines_by_variable_name(variable_name)
        end

        lines
      end

      def optional_lines_by_variable_name(variable_name)
        optional_triples = optional_triple_by_variable_name(variable_name)
        return [] if optional_triples.values.flatten.empty?

        left_indent = ' ' * 4
        lines = ["#{left_indent}OPTIONAL {"]
        optional_triples.each do |subject_name, triples|
          next if triples.empty?

          optional_triples[subject_name].each do |triple|
            lines << triple.to_sparql(' ' * 4,
                                      triple.object == triples.first.object,
                                      triple.object == triples.last.object,
                                      left_indent)
          end
        end
        lines << "#{left_indent}}"

        lines
      end

      def values_lines
        @values_lines.uniq
      end

      def values_line(variavale_name, value)
        "#{@@indent_text}VALUES #{variavale_name} { #{value} }"
      end

      def use_property_path?(bnode_rdf_types)
        flatten = bnode_rdf_types.flatten
        flatten.uniq.size == 1 && flatten.first.nil?
      end

      def add_triple(triple, is_optional)
        return if (triple.predicate.strip.to_s.size == 0) || (triple.subject.name == triple.object.name)

        case triple
        when Array
          triple.each do |t|
            add_triple(t, is_optional)
          end
        else
          triple_for_subject_rdf_type = Triple.new(triple.subject, 'a', triple.subject)
          object = model.find_object(triple.object.name)
          triple_for_object_rdf_type = if object.is_a?(Model::Subject)
                                         subject = subject_instance(object, object.types)
                                         Triple.new(subject, 'a', subject)
                                       else
                                         nil
                                       end
          if is_optional
            @optional_triples << triple_for_subject_rdf_type unless @optional_triples.include?(triple_for_subject_rdf_type)
            @optional_triples << triple_for_object_rdf_type if !triple_for_object_rdf_type.nil? && !@optional_triples.include?(triple_for_object_rdf_type)
            @optional_triples << triple unless @optional_triples.include?(triple)
          else
            @required_triples << triple_for_subject_rdf_type unless @required_triples.include?(triple_for_subject_rdf_type)
            @required_triples << triple_for_object_rdf_type if !triple_for_object_rdf_type.nil? && !@required_triples.include?(triple_for_object_rdf_type)
            @required_triples << triple unless @required_triples.include?(triple)
          end
        end
      end

      def subject_in_model_by_variable_instance(variable)
          @model.find_subject(variable.name) ||
            @model.subjects.select { |subject| subject.as_object.values.map(&:name).include?(variable.name) }.first
      end

      def triples_has_subject?(triples, subject)
        !triples.map(&:subject).select { |subj| subj == subject }.empty?
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
            v_inst = variable_instance(variable_name_for_sparql(subject.name))
          end

          v_inst.rdf_types = rdf_types if !rdf_types.nil?

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
        @variable[variable_name] = Variable.new(variable_name)
      end

      def blank_node(predicate_routes, rdf_types)
        bnodes = @blank_nodes.select { |bnode| bnode.predicate_routes == predicate_routes && bnode.rdf_types == rdf_types }
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
        @required_triples + @optional_triples
      end

      def template?
        @opts.key?(:template) && @opts[:template] == true
      end

      def indent(depth_increment = 0)
        "#{@@indent_text * (@depth + depth_increment)}"
      end

      def hidden_variables_bak
        []
      end

      def optional?(object_name, start_subject = nil)
        model.predicate_path(object_name, start_subject).select { |p| !p.required? }.size > 0
      end

      def optional_triple_by_variable_name(variable_name)
        optional_triple = {}

        triples_in_model = model.triples_by_object_name(variable_name)
        subject_names = triples_in_model.map(&:subject).map(&:name)
        triples_in_model.each do |triple_in_model|
          unless optional_triple.key?(triple_in_model.subject.name)
            optional_triple[triple_in_model.subject.name] = []
          end
          @optional_triples.each do |ot|
            next if @required_triples.include?(ot)

            if ot.rdf_type?
              if subject_names.include?(ot.subject.name) && triple_in_model.subject.name == ot.subject.name
                optional_triple[triple_in_model.subject.name] << ot
              end
            else
              case triple_in_model.object
              when Model::Subject
                optional_triple[triple_in_model.subject.name] << ot if triple_in_model.object.name == ot.object.name
              when Model::ValueList
                if triple_in_model.object.value.map(&:name).include?(ot.object.name) && subject_names.include?(ot.object.name)
                  optional_triple[triple_in_model.subject.name] << ot
                end
              else
                optional_triple[triple_in_model.subject.name] << ot if triple_in_model.object.name == ot.object.name
              end
            end
          end
        end

        optional_triple
      end
    end
  end
end

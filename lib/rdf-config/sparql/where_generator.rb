class RDFConfig
  class SPARQL
    class WhereGenerator < SPARQL
      INDENT_TEXT = '    '.freeze
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

        def to_sparql(indent = '', is_first_triple = true, is_last_triple = true)
          line = if is_first_triple
                   "#{indent}#{subject.to_sparql} "
                 else
                   "#{indent * 2}"
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
          "#{to_sparql}_class"
        end

        def ==(other)
          @name == other.name
        end
      end

      class BlankNode
        include RDFType

        attr_reader :rdf_types

        def initialize(bnode_id)
          @bnode_id = bnode_id
        end

        def name
          "_b#{@bnode_id}"
        end

        def to_sparql
          "_:b#{@bnode_id}"
        end

        def rdf_type_varname
          "?#{name}_class"
        end

        def ==(other)
          name == other.name
        end
      end

      def initialize(config, opts = {})
        super

        @values_lines = []
        @required_triples = []
        @optional_triples = []

        @variable = {}
        @blank_node = {}

        @bnode_number = 1
        @depth = 1
      end

      def generate
        generate_triples
        add_values_lines

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
        variables.each do |variable_name|
          next if model.subject?(variable_name)

          triple_in_model = model.find_by_object_name(variable_name)
          next if triple_in_model.nil?

          object = triple_in_model.object
          if object.is_a?(RDFConfig::Model::Subject)
            subject = variable(object.name)
            subject.rdf_types = object.types
            add_triple(Triple.new(subject, nil, variable('')), false)
          end

          if triple_in_model.bnode_connecting?
            generate_triples_with_bnode(triple_in_model)
          else
            generate_triple_without_bnode(triple_in_model)
          end
        end
      end

      def generate_triple_without_bnode(triple_in_model)
        subject = subject_instance(triple_in_model.subject)
        subject.rdf_types = triple_in_model.subject.types

        add_triple(Triple.new(subject,
                              triple_in_model.predicates.first.uri,
                              variable(triple_in_model.object.name)),
                   optional_phrase?(triple_in_model.predicate))
      end

      def generate_triples_with_bnode(triple_in_model)
        bnode_rdf_types = model.bnode_rdf_types(triple_in_model)

        if use_property_path?(bnode_rdf_types)
          add_triple(Triple.new(subject_instance(triple_in_model.subject),
                                triple_in_model.property_path(PROPERTY_PATH_SEP),
                                variable(triple_in_model.object_name)),
                     optional_phrase?(triple_in_model.predicate)
          )
        else
          generate_triples_with_bnode_rdf_types(triple_in_model, bnode_rdf_types)
        end
      end

      def generate_triples_with_bnode_rdf_types(triple_in_model, bnode_rdf_types)
        predicates = triple_in_model.predicates

        subject = subject_instance(triple_in_model.subject)
        subject.rdf_types = triple_in_model.subject.types

        bnode_predicates = []
        (0...predicates.size - 1).each do |i|
          bnode_predicates << predicates[i]
          rdf_types = bnode_rdf_types[i]
          next if rdf_types.nil?

          object = blank_node(predicates[0..i])
          add_triple(Triple.new(subject,
                                bnode_predicates.map(&:uri).join(PROPERTY_PATH_SEP),
                                object),
                     false)
          bnode_predicates.clear
          subject = object
          subject.rdf_types = bnode_rdf_types[i]
        end

        object = variable(triple_in_model.object_name)
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
        @model.subjects.each do |subject_in_model|
          subjects = @required_triples.map(&:subject).select { |subject| subject.name == subject_in_model.name }
          next if subjects.empty?

          lines += lines_by_subject(subjects.first)
        end

        @required_triples.map(&:subject).select { |subject| subject.is_a?(BlankNode) }.uniq.each do |subject|
          lines += lines_by_subject(subject)
        end

        lines
      end

      def lines_by_subject(subject)
        lines = []

        triples = @required_triples.select { |triple| triple.subject == subject }
        return [] if triples.empty?

        if subject.has_rdf_type?
          triples = [Triple.new(subject, 'a', subject)] + triples
          triples.reject! { |triple| triple.predicate.nil? }
        end

        triples.each do |triple|
          lines << triple.to_sparql(indent,
                                    triple.object == triples.first.object,
                                    triple.object == triples.last.object)
        end

        lines
      end

      def optional_lines
        lines = []
        @optional_triples.each do |triple|
          lines << "#{indent}OPTIONAL{ #{triple.to_sparql} }"
        end

        lines
      end

      def values_lines
        @values_lines.uniq
      end

      def values_line(variavale_name, value)
        "#{INDENT_TEXT}VALUES #{variavale_name} { #{value} }"
      end

      def use_property_path?(bnode_rdf_types)
        flatten = bnode_rdf_types.flatten
        flatten.uniq.size == 1 && flatten.first.nil?
      end

      def add_triple(triple, is_optional)
        case triple
        when Array
          triple.each do |t|
            add_triple(t, is_optional)
          end
        else
          if is_optional
            @optional_triples << triple unless @optional_triples.include?(triple)
          else
            @required_triples << triple unless @required_triples.include?(triple)
          end
        end
      end

      def subject_instance(subject_in_model)
        if subject_in_model.blank_node? && subject_in_model.types.size > 1
          blank_node(subject_in_model.predicates)
        else
          variable(subject_in_model.name)
        end
      end

      def variable(variable_name)
        if @variable.key?(variable_name)
          @variable[variable_name]
        else
          add_variable(variable_name)
        end
      end

      def add_variable(variable_name)
        @variable[variable_name] = Variable.new(variable_name)
      end

      def blank_node(predicates)
        if @blank_node.key?(predicates)
          @blank_node[predicates]
        else
          add_blank_node(predicates)
        end
      end

      def add_blank_node(predicates)
        bnode = BlankNode.new(@bnode_number)
        @blank_node[predicates] = bnode
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
        "#{INDENT_TEXT * (@depth + depth_increment)}"
      end
    end
  end
end

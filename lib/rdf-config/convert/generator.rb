# frozen_string_literal: true

require_relative 'mix_in/convert_util'

class RDFConfig
  class Convert
    class Generator
      include RDFConfig::Convert::MixIn::ConvertUtil

      READ_DONE_LINES = 1000

      def initialize(config, convert)
        @config = config
        @convert = convert
        @reader = nil
        @converter = convert.rdf_converter

        @model = Model.instance(@config)
        @prefixes = @config.prefix.transform_values { |uri| RDF::URI.new(uri[1..-2]) }
        @prefixes[:xsd] = RDF::URI.new('http://www.w3.org/2001/XMLSchema#')

        @source = nil
        @subject_convert = nil
        @is_subject_splitted = false

        @subject_node = {}
        @subject_names = []
        @object_names = []
        @object_triple_map = {}

        @bnode_id = 0
        @bnode = {}
      end

      def inspect
        "#<#{self.class}:0x#{object_id.to_s(16)}>"
      end

      private

      def generate_by_row(row)
        clear_subject_node

        process_convert_variables(row)
        generate_by_subjects(row)
        generate_subject_relation
      end

      def process_convert_variables(row)
        @convert.convert_variable_names.each do |variable_name|
          converts = @convert.variable_convert.select { |key, value| key == variable_name }
          next if converts.empty?

          @converter.convert_value(row, converts, false)
        end
      end

      def generate_by_subjects(row)
        @subject_names.each do |subject_name|
          @subject_convert = subject_convert_for(subject_name)
          @is_subject_splitted = subject_convert_has_split_method?
          generate_by_subject(row, subject_name)
        end
      end

      def generate_by_subject(row, subject_name)
        subject = @model.find_subject(subject_name)
        if subject.blank_node?
          generate_by_bnode_subject(subject_name, row, @subject_convert)
        else
          return if @subject_convert.nil?

          subject_uris = @converter.convert_value(row, @subject_convert, true)
          return if subject_uris.to_s.empty?

          subject_uris = [subject_uris] unless subject_uris.is_a?(Array)
          subject_uris.each do |subject_uri|
            generate_subject(subject_name, subject_uri)
          end

          generate_by_objects(subject_name, row)
        end
      end

      def generate_by_bnode_subject(subject_name, row, subject_convert)
        if subject_convert.nil?
          generate_bnode_subject(subject_name)
        else
          subject_uris = Array(@converter.convert_value(row, subject_convert))
          subject_uris.each do |subject_uri|
            generate_subject(subject_name, subject_uri)
          end
        end

        generate_by_objects(subject_name, row)
      end

      def generate_by_objects(subject_name, row)
        object_converts_for(subject_name).each do |object_name, object_converts|
          # next if @converter.converter_variable?(object_name)

          generate_by_object_convert(row, object_name.to_s, object_converts)
        end
      end

      def generate_by_object_convert(row, object_name, object_converts)
        if convert_variable?(object_name)
          @converter.convert_value(row, object_converts, false)
          return
        end

        triple = triple_by_object(object_name)
        return if triple.nil?

        subject_name = triple.subject.name
        return unless @subject_node.key?(subject_name)

        values = @converter.convert_value(row, object_converts, triple.object_is_uri?)
        if values.is_a?(Array) && @is_subject_splitted
          if values.size != @subject_node[subject_name].size
            warn split_count_mismatch_warning(row, subject_name, object_name, object_converts, values)
          end

          if @subject_node[subject_name].size > values.size
            (@subject_node[subject_name].size - values.size).times { values << '' }
          elsif @subject_node[subject_name].size < values.size
            values = values[0..@subject_node[subject_name].size - 1]
          end
        end

        values = Array.new(@subject_node[subject_name].size, values) unless values.is_a?(Array)
        values.each_with_index do |value, idx|
          next if value.to_s.empty?

          generate_by_triple(triple, values, idx)
        end
      end

      def split_count_mismatch_warning(row, subject_name, object_name, object_converts, values)
        subject_column = ''
        subject_value = ''
        col_convert = @subject_convert.select { |convert| convert[:method_name_] == 'col' }.first
        unless col_convert.nil?
          subject_column = col_convert[:args_][:arg_].to_s[1..-2]
          subject_value = row[subject_column]
        end

        object_column = ''
        object_value = ''
        col_convert = object_converts.select { |convert| convert[:method_name_] == 'col' }.first
        unless col_convert.nil?
          object_column = col_convert[:args_][:arg_].to_s[1..-2]
          object_value = row[object_column]
        end

        warning = ["Warning: split count mismatch at #{@reader.source_name}:#{@reader.line_no}:"]
        warning << "subject '#{subject_name}' (count=#{@subject_node[subject_name].size},"
        warning << %Q/cols: #{subject_column}="#{subject_value}")/
        warning << 'vs'
        warning << "object '#{object_name}' (count=#{values.size},"
        warning << %Q/cols: #{object_column}="#{object_value}")/

        warning.join(' ')
      end

      def triple_by_object(object_name)
        unless @object_triple_map.key?(object_name)
          @object_triple_map[object_name] = @model.find_by_object_name(object_name)
        end

        @object_triple_map[object_name]
      end

      def generate_subject_relation
        @subject_node.each_key do |subject_name|
          @model.find_all_by_object_name(subject_name).each do |triple|
            next unless @subject_node.key?(triple.subject.name)

            generate_one_subject_relation(triple, @subject_node[triple.subject.name], @subject_node[subject_name])
          end
        end
      end

      def generate_one_subject_relation(triple, subject_nodes, object_nodes)
        if @convert.split_subject[triple.object.name] == false
          generate_multi2one_subject_relation(triple, subject_nodes, object_nodes)
        else
          if subject_nodes.size == 1
            generate_one2multi_subject_relation(triple, subject_nodes.first, object_nodes)
          else
            generate_one2one_subject_relation(triple, subject_nodes, object_nodes)
          end
        end
      end

      def generate_multi2one_subject_relation(triple, subject_nodes, object_nodes)
        subject_nodes.each do |subject_node|
          add_subject_relation(triple, subject_node, object_nodes.first)
        end
      end

      def generate_one2multi_subject_relation(triple, subject_node, object_nodes)
        object_nodes.each do |object_node|
          add_subject_relation(triple, subject_node, object_node)
        end
      end

      def generate_one2one_subject_relation(triple, subject_nodes, object_nodes)
        subject_nodes.zip(object_nodes) do |nodes|
          break if nodes[1].nil?

          add_subject_relation(triple, nodes[0], nodes[1])
        end
      end

      def subject_convert_has_split_method?
        @subject_convert.select { |convert| convert[:method_name_].to_s == 'split' }.any?
      end

      def subject_convert_for(subject_name)
        @convert.convert_method[:subject_converts][[subject_name, @source]]
      end

      def object_converts_for(subject_name)
        @convert.convert_method[:object_converts][[subject_name, @source]]
      end

      def add_subject_node(subject_name, subject_node)
        @subject_node[subject_name] = [] unless @subject_node.key?(subject_name)
        @subject_node[subject_name] << subject_node
      end

      def clear_subject_node
        @subject_node.clear
      end

      def generate_bnode_id
        @bnode_id += 1
      end

      def bnode_uri
        "_:b#{@bnode_id}"
      end

      def bnode_key(subject, property_path)
        [subject.to_s, property_path].join("\t")
      end

      def clear_bnode_cache
        @bnode = {}
      end
    end
  end
end

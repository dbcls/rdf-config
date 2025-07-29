# frozen_string_literal: true

require 'psych'
require_relative 'scalar_node'
require_relative '../../convert'

class RDFConfig
  class Convert
    class Yaml
      class Parser
        attr_reader :yaml_file, :nodes_doc, :converts, :errors

        def initialize(yaml_file)
          @yaml_file = yaml_file
          @nodes_doc = Psych.parse_file(yaml_file)

          @errors = []

          unless @nodes_doc.children.size == 1 && @nodes_doc.children.first.is_a?(Psych::Nodes::Sequence)
            add_error("#{@yaml_file} must be an array of conversion settings for each subject.")
            raise InvalidConfig, Validator.format_error_message(@errors)
          end

          @converts = []
          @convert = {}
        end

        def parse
          # children of @nodes_doc are root node (Array)
          root_node = @nodes_doc.children.first

          # children of root_node are array of a subject
          root_node.children.each do |subject_mapping|
            @convert = {}
            @source = nil
            parse_subject(subject_mapping)
            @converts << @convert
          end

          validate
        end

        def subject_names
          @converts.map { |convert| convert[:subject_name] }.uniq
        end

        def object_names
          @converts.map { |convert| convert[:object_convert] }
                   .map { |object_converts| object_converts.map(&:keys) }
                   .flatten.uniq
        end

        def variable_names
          subject_names + object_names
        end

        def error?
          @errors.size > 0
        end

        def dump
          @converts.each do |convert|
            puts "Subject name: #{convert[:subject_name].inspect}"
            puts '  pre process'
            convert[:pre_process].each do |pre_process|
              puts ['    ', pre_process.inspect].join
            end

            puts '  subject convert'
            convert[:subject_convert].each do |subject_convert|
              puts ['    ', subject_convert.inspect].join
            end

            puts '  object convert'
            convert[:object_convert].each do |object_converts|
              object_converts.each do |object_name, object_convert_rules|
                puts ['    ', object_name.inspect].join
                object_convert_rules = [object_convert_rules] unless object_convert_rules.is_a?(Array)
                object_convert_rules.each do |object_convert|
                  puts ['      ', object_convert.inspect].join
                end
              end
            end

            puts
          end
        end

        private

        def parse_subject(subject_mapping)
          unless subject_mapping.is_a?(Psych::Nodes::Mapping)
            add_error("Invalid subject config.")
            return
          end

          subject_name = subject_mapping.children[0].value
          unless subject_mapping.children.size == 2
            add_error("Invalid subject config: #{subject_name}")
            return
          end

          unless subject_mapping.children[1].is_a?(Psych::Nodes::Sequence)
            add_error("Subject convert config must be an array: #{@subject_name}")
            return
          end

          @convert[:subject_name] = subject_name
          @convert[:pre_process] = []
          @convert[:subject_convert] = []
          @convert[:object_convert] = []

          # subject rules are preprocessed_rules, subject_convert_rules or object_convert_rules
          subject_rules = subject_mapping.children[1].children
          subject_rules.each do |subject_rule|
            case subject_rule
            when Psych::Nodes::Scalar
              parse_pre_process_convert(subject_rule)
            when Psych::Nodes::Mapping
              key = subject_rule.children[0].value
              if key == 'subject'
                parse_subject_converts(subject_rule.children[1])
              elsif key == 'objects'
                parse_object_converts(subject_rule.children[1])
              else
                parse_pre_process_convert(subject_rule)
              end
            else
              add_error("Invalid subject_config: #{@subject_name}")
            end
          end
        end

        def parse_pre_process_convert(pre_process_convert)
          case pre_process_convert
          when Psych::Nodes::Scalar
            @convert[:pre_process] << ScalarNode.new(pre_process_convert)
          when Psych::Nodes::Mapping
            convert = node_to_ruby(pre_process_convert)
            @convert[:pre_process] << convert.map { |k, v| v.is_a?(Array) ? [k, v] : [k, [v]] }.to_h
          end
        end

        def parse_subject_converts(subject_converts)
          converts = node_to_ruby(subject_converts)
          if converts.is_a?(Array)
            @convert[:subject_convert] = converts
          else
            @convert[:subject_convert] = [converts]
          end
        end

        def parse_object_converts(object_converts)
          unless object_converts.is_a?(Psych::Nodes::Sequence)
            add_error("Convert config of objects must be an array.")
            return
          end

          object_converts.children.each do |object_convert|
            parse_object_convert(object_convert)
          end
        end

        def parse_object_convert(object_convert)
          unless object_convert.is_a?(Psych::Nodes::Mapping)
            add_error("Convert config of object must be an hash.")
            return
          end

          unless object_convert.children.size == 2
            add_error("Convert config of object must be an hash.")
            return
          end

          object_name = ScalarNode.new(object_convert.children[0])
          object_convert_rule = node_to_ruby(object_convert.children[1])
          @convert[:object_convert] << { object_name.to_s => object_convert_rule }
        end

        def node_to_ruby(node)
          case node
          when Psych::Nodes::Scalar
            ScalarNode.new(node)
          when Psych::Nodes::Sequence
            node.children.map { |child| node_to_ruby(child) }
          when Psych::Nodes::Mapping
            node.children.each_slice(2).map do |key_node, value_node|
              [node_to_ruby(key_node), node_to_ruby(value_node)]
            end.to_h
          else
            raise "Unsupported node type: #{node.class}"
          end
        end

        def validate
          if @converts.size == 0
            add_error("No configuration found for convert.")
          else
            @converts.each do |convert|
              if convert[:subject_convert].nil? || convert[:subject_convert].empty?
                add_error("No subject convert found for subject #{convert[:subject_name]}")
              end

              if convert[:object_convert].nil? || convert[:object_convert].empty?
                add_error("No object convert found for subject #{convert[:subject_name]}")
              end
            end
          end

          raise InvalidConfig, Validator.format_error_message(@errors) if error?
        end

        def add_error(msg)
          @errors << msg
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  parser = RDFConfig::Convert::Yaml::Parser.new(ARGV[0])
  parser.parse
  parser.dump
end

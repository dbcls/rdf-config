# frozen_string_literal: true

require 'psych'
require_relative 'scalar_node'

class RDFConfig
  class Convert
    class Yaml
      class Parser
        attr_reader :yaml_file, :subject_names, :object_name, :nodes_doc, :errors,
                    :pre_process, :subject_convert, :object_convert

        def initialize(yaml_file)
          @yaml_file = yaml_file
          @nodes_doc = Psych.parse_file(yaml_file)

          @subject_names = []
          @object_name = {}

          @pre_process = {}
          @subject_convert = {}
          @object_convert = {}

          @subject_name = nil
          @errors = []
        end

        def parse
          # children of @nodes_doc are root node (Array)
          root_node = @nodes_doc.children.first

          # children of root_node are array of a subject
          root_node.children.each do |subject_mapping|
            parse_subject(subject_mapping)
          end
        end

        def object_names
          @object_name.values.flatten.map(&:to_s)
        end

        def variable_names
          @subject_names + object_names
        end

        def error?
          @errors.size > 0
        end

        def parse_subject(subject_mapping)
          unless subject_mapping.is_a?(Psych::Nodes::Mapping)
            add_error("Invalid subject config.")
            return
          end

          @subject_name = subject_mapping.children[0].value
          @subject_names << @subject_name
          unless subject_mapping.children.size == 2
            add_error("Invalid subject config: #{@subject_name}")
            return
          end

          unless subject_mapping.children[1].is_a?(Psych::Nodes::Sequence)
            add_error("Subject convert config must be an array: #{@subject_name}")
            return
          end

          @pre_process[@subject_name] = []
          @object_convert[@subject_name] = {}

          # subject rules are preprocessed_rules, subject_convert_rules or object_convert_rules
          subject_rules = subject_mapping.children[1].children
          subject_rules.each do |subject_rule|
            case subject_rule
            when Psych::Nodes::Scalar
              @pre_process[@subject_name] << ScalarNode.new(subject_rule)
            when Psych::Nodes::Mapping
              key = subject_rule.children[0].value
              if key == 'subject'
                parse_subject_converts(subject_rule.children[1])
              elsif key == 'objects'
                parse_object_converts(subject_rule.children[1])
              else
                @pre_process[@subject_name] << node_to_ruby(subject_rule)
              end
            else
              add_error("Invalid subject_config: #{@subject_name}")
            end
          end
        end

        def parse_subject_converts(subject_converts)
          converts = node_to_ruby(subject_converts)
          if converts.is_a?(Array)
            @subject_convert[@subject_name] = converts
          else
            @subject_convert[@subject_name] = [converts]
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
          add_object_name(object_name)
          object_convert_rule = node_to_ruby(object_convert.children[1])
          @object_convert[@subject_name][object_name] =
            object_convert_rule.is_a?(Array) ? object_convert_rule : [object_convert_rule]
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

        def subject_converts(subject_name)
          @pre_process[subject_name] + @subject_convert[subject_name]
        end

        def add_object_name(object_name)
          @object_name[@subject_name] ||= []

          @object_name[@subject_name] << object_name.to_s
        end

        def add_error(msg)
          @errors << msg
        end

        def dump
          puts '----- pre process -----'
          @pre_process.each do |subject, rules|
            puts subject
            rules.each do |rule|
              puts "  #{rule.inspect}"
            end
          end
          puts

          puts '----- subject convert -----'
          @subject_convert.each do |subject, rules|
            puts subject
            rules.each do |rule|
              puts "  #{rule.inspect}"
            end
          end
          puts

          puts '----- object convert -----'
          @object_convert.each do |subject_name, object_convert|
            puts subject_name
            object_convert.each do |object_name, object_rules|
              puts "  #{object_name}"
              object_rules.each do |object_rule|
                puts "    #{object_rule.inspect}"
              end
            end
          end
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

# frozen_string_literal: true

class RDFConfig
  class Convert
    class JsonLdGenerator
      class NestGenerator
        def initialize(model, node)
          @model = model
          @node = node

          @subject_names = @model.subject_names

          @nested_nodes = []
        end

        def generate
          root_subjects.each do |subject_name|
            @node.select { |_, object_hash| object_hash.keys.include?(subject_name) }.each_value do |object_hash|
              @nested_nodes << process_node(object_hash)
            end
          end

          @nested_nodes
        end

        def process_node(node)
          new_node = {}
          subject_name = subject_name_by_node(node)
          node.each do |variable_name, value|
            new_value = object_value(subject_name, variable_name, value)
            next if new_value.nil? || (new_value.is_a?(Array) && new_value.empty?)

            new_node[variable_name] = if new_value.is_a?(Array) && new_value.size == 1
                                        new_value.first
                                      else
                                        new_value
                                      end
          end

          new_node
        end

        def object_value(subject_name, variable_name, value)
          return value if [subject_name, '@type'].include?(variable_name)

          triple = @model.find_by_object_name(variable_name)
          return if triple.nil?

          if triple.object.is_a?(Model::Subject) || triple.object.is_a?(Model::ValueList)
            Array(value).map do |v|
              if @node.key?(v)
                process_node(@node[v])
              else
                v
              end
            end
          else
            value
          end
        end

        def subject_name_by_node(node)
          node.keys.find { |name| @subject_names.include?(name) }
        end

        def root_subjects
          object_subjects = []
          @model.each do |triple|
            if triple.object.is_a?(Model::Subject)
              object_subjects << triple.object.name
            elsif triple.object.is_a?(Model::ValueList)
              triple.object.values.each do |object_subject|
                object_subjects << object_subject.name if object_subject.is_a?(Model::Subject)
              end
            end
          end

          @model.subjects.map(&:name) - object_subjects.uniq
        end
      end
    end
  end
end

class RDFConfig
  class Convert
    class Converter
      attr_reader :path_variable_map, :root_paths, :path_relation

      def initialize(convert_method)
        @convert_method = convert_method
        @target_value = []

        @path = {}
        @path_variable_map = {}
        @paths = []
        @root_paths = []
        @path_relation = {}

        set_path_variable_map
        set_paths
        set_path_relation
      end

      def convert_row(row)
        converted_value = {}
        @convert_method.each do |variable_name, methods|
          @target_value = row
          exec_convert_process(methods)
          converted_value[variable_name] = @target_value
        end

        converted_value
      end

      def exec_convert_process(methods)
        methods.each do |method_def|
          exec_method(method_def)
        end
      end

      def convert_value(row, variable_name)
        @target_value = row
        @convert_method[variable_name].each do |method_def|
          exec_method(method_def)
        end

        @target_value
      end

      def exec_method(method_def)
        unless respond_to?(method_def[:method_name_])
          require_relative "macros/#{method_def[:method_name_]}.rb"
          self.class.define_method(
            method_def[:method_name_].to_sym, self.class.instance_method(method_def[:method_name_].to_sym)
          )
        end

        args = if method_def.key?(:args_)
                 case method_def[:args_]
                 when Hash
                   [arg_value(method_def[:args_][:arg_])]
                 when Array
                   method_def[:args_].map { |arg| arg_value(arg[:arg_]) }
                 else
                   []
                 end
               else
                 []
               end

        exec_converter(method_def[:method_name_], *args)
      end

      def exec_converter(name, *args)
        @target_value = if @target_value.is_a?(Array)
                          @target_value.map { |v| call_convert_method(name, v, *args) }
                        else
                          call_convert_method(name, @target_value, *args)
                        end
      end

      def call_convert_method(method_name, target_value, *args)
        if target_value.to_s.empty?
          ''
        else
          send(method_name, target_value, *args)
        end
      end

      def arg_value(parslet_slice)
        value = parslet_slice.to_str
        if value =~ /\A\d+\z/
          value.to_i
        elsif value[0] == '"' || value[0] == "'"
          value[1..-2]
        else
          value
        end
      end

      def variable_names
        @convert_method.keys
      end

      def variable?(variable_name)
        variable_names.include?(variable_name)
      end

      def clear_value
        @target_value = nil
      end

      def set_path_variable_map
        @convert_method.each do |variable_name, convert_defs|
          convert_defs.each do |convert_def|
            next unless macro_names.include?(convert_def[:method_name_].to_str)

            # path = convert_def[:args_][:arg_].to_str[1..-2]
            path = extract_path(convert_def[:args_][:arg_].to_str[1..-2])
            @path[variable_name] = path

            @path_variable_map[path] = [] unless @path_variable_map.key?(path)
            @path_variable_map[path] << variable_name
          end
        end
      end

      def set_path_relation
        not_root_paths.reverse.each do |child|
          parent = nil
          (@paths - [child]).reverse.each do |target|
            next unless child.start_with?(target)

            parent = target
            if @path_relation.key?(parent)
              @path_relation[parent] << child
            else
              @path_relation[parent] = [child]
            end
            break
          end

          @root_paths << child if parent.nil? && !@root_paths.include?(child)
        end
      end

      def set_paths
        @paths = @path_variable_map.keys.sort { |a, b| a.split(path_separator).length <=> b.split(path_separator).length }
        @root_paths = @paths.select { |path| @paths[0].split(path_separator).size == path.split(path_separator).size }
      end

      def extract_path(path)
        path
      end

      def not_root_paths
        @paths.reject { |path| @paths[0].split(path_separator).size == path.split(path_separator).size }
      end

      def path_by_variable_name(variable_name)
        @path[variable_name]
      end
    end
  end
end

class RDFConfig
  class SPARQL
    class Variable
      PropertyPath = Struct.new(:subject, :path)

      attr_reader :config_name, :name, :value, :property_path

      def initialize(config, variable)
        @config = config

        @config_name = ''
        @name = ''
        @value = nil
        @required = false
        @property_path = nil

        parse_variable(variable.to_s)
      end

      def variable?
        @value.nil?
      end

      def parameter?
        !@value.nil?
      end

      def required?
        @required
      end

      def eql?(other)
        self.name == other.name
      end

      def ==(other)
        self.name == other.name
      end

      private

      def parse_variable(variable)
        conf_var_val, subject, path = variable.to_s.split(/\s+/, 3)

        # TODO !subject.nil? && path.nil? の場合、property pathの設定エラー

        conf_var, @value = conf_var_val.split('=', 2)
        @value = nil if @value.is_a?(String) && @value.strip.empty?

        @config_name, @name = conf_var.split(':')
        if @name.nil?
          @config_name = @config.name
          @name = conf_var
        end

        if @name[-1] == '!'
          @name = @name[0..-2]
          @required = true
        end

        if subject && path
          @property_path = PropertyPath.new(subject, path)
        end
      end

      def parse_variable_old(variable)
        conf_var_name, @value = variable.split('=', 2)
        @value = nil if @value.is_a?(String) && @value.strip.empty?

        @config_name, variable_name = conf_var_name.split(':')
        if variable_name.nil?
          @config_name = @config.name
          variable_name = conf_var_name
        end
        matched = /\A(?<name>\w+)(?<required>!?)(\s+(?<property_path>.+))?\z/.match(variable_name)

        if matched.nil?
          @name = variable
        else
          @name = matched[:name]
          @required = matched[:required].to_s == '!'
          @property_path = matched[:property_path]
        end
      end
    end
  end
end

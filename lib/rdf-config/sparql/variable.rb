class RDFConfig
  class SPARQL
    class Variable
      PropertyPath = Struct.new(:subject, :path)

      attr_reader :config_name, :name, :value, :property_path

      def initialize(config, variable, as_subject: false)
        @config = config
        @as_subject = as_subject

        @config_name = ''
        @name = ''
        @value = nil

        @required = false
        @property_path = nil

        parse_variable(variable.to_s)
      end

      def visible_variables
        if property_path_exist?
          [@property_path.subject, @name]
        else
          [@name]
        end
      end

      def subject_of_property_path?
        @as_subject
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

      def property_path_exist?
        !@property_path.nil?
      end

      def eql?(other)
        name == other.name
      end

      def ==(other)
        name == other.name
      end

      private

      def parse_variable(variable)
        if /\A(?<subject>\w+)\s+(?<property_path>.+)\s+(?<conf_var_val>.+)/ =~ variable
          # variable includes property path
          @property_path = PropertyPath.new(subject, property_path)
        else
          conf_var_val = variable
        end

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
      end
    end
  end
end

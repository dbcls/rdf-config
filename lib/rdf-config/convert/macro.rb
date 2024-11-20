# frozen_string_literal: true

class RDFConfig
  class Convert
    class Macro
      class << self
        def get_instance(*macro_names)
          @macro_names = macro_names
          @required_macros = []
          macro_names.each do |macro_name|
            next if SYSTEM_MACRO_NAMES.include?(macro_name)

            add_macro(macro_name)
          end

          @required_macros.each do |macro_name|
            add_macro(macro_name)
          end

          new
        end

        def macro_file_path(macro_name)
          File.join(MACRO_DIR_PATH, "#{macro_name}.rb")
        end

        private

        def add_macro(macro_name)
          def_lines = []
          File.foreach(macro_file_path(macro_name)) do |line|
            line.strip!
            if line.start_with?('require')
              method, feature = line.split(/\s+/, 2)
              feature = class_eval(feature)
              if method == 'require'
                if %r{\A\./?<macro>([a-z0-9]+)\z} =~ feature && !@macro_names.include?(macro)
                  @required_macros << macro
                else
                  class_eval(line)
                end
              elsif method == 'require_relative'
                @required_macros << feature unless @macro_names.include?(feature)
              end
            else
              def_lines << line
            end
          end

          class_eval(def_lines.join("\n"))
        end
      end
    end
  end
end

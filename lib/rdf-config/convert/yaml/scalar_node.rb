# frozen_string_literal: true

class RDFConfig
  class Convert
    class Yaml
      class ScalarNode
        attr_reader :value

        def initialize(node)
          @node = node
          @value = if node.value =~ /\A\d+\z/
                     node.value.to_i
                   elsif node.value =~ /\A\d+\.\d+\z/
                     node.value.to_f
                   else
                     node.value
                   end
          @quoted = node.quoted
        end

        def to_s
          @value.to_s
        end

        def quoted?
          @quoted
        end

        def inspect
          "<ScalarNode #{@value}, @quoted: #{@quoted}>"
        end
      end
    end
  end
end

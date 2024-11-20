# frozen_string_literal: true

class RDFConfig
  class Model
    class Cardinality
      attr_reader :quantifier, :min, :max

      def initialize(quantifier)
        @quantifier = quantifier.to_s.strip

        @min = 1
        @max = 1

        parse
      end

      def parse
        case @quantifier
        when '*'
          @min = 0
          @max = nil
        when '+'
          @min = 1
          @max = nil
        when '?'
          @min = 0
          @max = 1
        when /\A\{(\d+)}\z/
          @min = @max = Regexp.last_match(1).to_i
        when /\A\{\s*(\d*)\s*,\s*(\d*)\s*}\z/
          @min = Regexp.last_match(1).to_i
          @max = Regexp.last_match(2).to_s.strip.empty? ? nil : Regexp.last_match(2).to_i
          @quantifier = "{#{@min},#{@max}}"
        end
      end

      def required?
        @min.positive?
      end

      def optional?
        !required?
      end

      def range
        if @min == @max
          "{#{@min}}"
        elsif @min.nil?
          "{,#{@max}}"
        elsif @max.nil?
          "{#{@min},}"
        else
          "{#{@min},#{@max}}"
        end
      end

      def <=>(other)
        if @min == other.min
          compare_by_max(other)
        else
          other.min <=> @min
        end
      end

      def compare_by_max(other)
        return 0 if @max.nil? && other.max.nil?

        if @max.nil?
          -1
        elsif other.max.nil?
          1
        else
          other.max <=> @max
        end
      end
    end
  end
end

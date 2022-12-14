require 'rexml/document'
require 'rdf-config/schema/chart/constant'
require 'rdf-config/schema/chart/svg_utils'
require 'rdf-config/schema/chart/tree_generator'
require 'rdf-config/schema/chart/title_generator'
require 'rdf-config/schema/chart/subject_generator'
require 'rdf-config/schema/chart/predicate_generator'
require 'rdf-config/schema/chart/loop_predicate_generator'
require 'rdf-config/schema/chart/class_node_generator'
require 'rdf-config/schema/chart/uri_node_generator'
require 'rdf-config/schema/chart/literal_node_generator'
require 'rdf-config/schema/chart/blank_node_generator'
require 'rdf-config/schema/chart/unknown_node_generator'
require 'rdf-config/schema/chart/prefix_generator'
require 'rdf-config/schema/chart/arc_generator'
require 'rdf-config/schema/chart/table/svg_generator'

class REXML::Element
  def add_attribute_by_hash(attr_hash)
    attr_hash.each do |name, value|
      add_attribute(name.to_s, value)
    end
  end
end

class RDFConfig
  class Schema
    class Chart
      class SchemaConfigNotFound < StandardError; end

      class InvalidSchemaOption < StandardError; end

      include SvgUtils

      Position = Struct.new(:x, :y)
      ArrowPosition = Struct.new(:x1, :y1, :x2, :y2)

      def initialize(config, opts = {})
        @config = config
        @schema_opt = opts[:schema_opt].to_s.strip
        @schema_name = nil
        @nest = false
        @display_type = :tree # :tree | :arc | :table
        @display_title = true
        @display_prefix = true

        interpret_opt(opts[:schema_opt].to_s) if opts.key?(:schema_opt)
      end

      def print_usage
        warn 'Usage: --schema schema_name[:type]'
        warn "Available schema names: #{@config.schema.keys.join(', ')}"
        warn 'Avanlable schema types: nest, table, arc'
      end

      def generate
        if @schema_opt.empty? && @config.exist?('schema')
          print_usage
          return
        end

        opts = {
          schema_name: @schema_name,
          variables: interpret_variables
        }

        case @display_type
        when :tree
          opts = opts.merge(nest: @nest)
          generator = TreeGenerator.new(@config, opts)
          generator.generate
        when :arc
          generator = ArcGenerator.new(@config, opts)
          generator.generate
        when :table
          generator = Table::SvgGenerator.new(@config, opts)
          generator.generate
        else
          # unsupported chart type
          raise StandardError, "ERROR: Unsupported chart type '#{@display_type}'."
        end

        model.print_warnings
      end

      private

      def interpret_opt(schema_opt)
        errors = []
        valid_options = %w[nest arc table]
        table_types = %w[arc table]

        option_names = schema_opt.strip.split(/\s*:\s*/)
        return if option_names.empty?

        schema_name = option_names.shift
        unless schema_name.empty?
          if @config.schema.key?(schema_name)
            @schema_name = schema_name
          else
            errors << "Schema name '#{schema_name}' is specified but not found in schema.yaml file."
          end
        end

        if (table_types & option_names).size == table_types.size
          errors << "Both 'arc' option and 'table' option cannot be specified."
        end

        option_names.each do |name|
          next if name.empty?

          if valid_options.include?(name)
            @nest = true if name == 'nest'
            @display_type = name.to_sym if table_types.include?(name)
            @display_title = false if name == 'no_title'
            @display_prefix = false if name == 'no_prefix'
          else
            errors << "Invalid option '#{name}' is specified."
          end
        end

        return if errors.empty?

        error_message = "ERROR:\n#{errors.map { |msg| "  #{msg}" }.join("\n")}"
        raise InvalidSchemaOption, error_message
      end

      def interpret_variables
        if !@schema_name.nil? && @config.schema[@schema_name].key?('variables')
          vars = @config.schema[@schema_name]['variables'].clone
          @config.schema[@schema_name]['variables'].each do |variable_name|
            next if model.subject?(variable_name)

            triple = model.find_by_object_name(variable_name)
            vars.delete(triple.subject.name) if vars.include?(triple.subject.name)
          end
          vars
        else
          []
        end
      end
    end
  end
end

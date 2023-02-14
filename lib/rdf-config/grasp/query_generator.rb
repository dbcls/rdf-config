require_relative '../config'
require_relative '../model'
require_relative 'base'
require_relative 'data_type'

class RDFConfig
  class Grasp
    class QueryGenerator < Base
      include DataType

      IRI_ARG_NAME = 'iri'.freeze
      SPACE = ' '.freeze
      INDENT = SPACE * 2

      def initialize(config, opts = {})
        super

        @prefix = @config.prefix
        @subjects = []
      end

      def generate
        lines = []
        subject_names_for_query.each do |subject_name|
          subject = @model.find_subject(subject_name)
          next if subject.value.to_s.empty?

          lines << generate_by_subject(subject)
          lines << ''
        end
        lines.pop

        ['query {', lines, '}'].flatten
      end

      def generate_by_subject(subject)
        lines = []

        objects = []
        case subject
        when Model::Subject
          @subjects.push(subject)
          lines << if depth == 1
                     %!#{indent}#{subject_type_name(@config, subject, add_namespace: @add_namespace)}(#{IRI_ARG_NAME}: "#{subject_value(subject)}") {!
                   else
                     "#{indent}#{subject.as_object_name} {"
                   end
          lines << "#{indent}#{INDENT}#{IRI_ARG_NAME}"
          objects = subject.objects(reject_rdf_type: true)
        when Model::BlankNode
          objects = subject.as_subject.objects(reject_rdf_type: true)
        end

        objects.each do |object|
          next if skip_object?(object)

          case object
          when Model::Subject
            lines += generate_by_subject(object)
          when Model::BlankNode
            lines += generate_by_subject(object)
          else
            lines << "#{indent}#{INDENT}#{object.name}"
          end
        end

        if subject.is_a?(Model::Subject)
          lines << "#{indent}}"
          @subjects.pop if subject.is_a?(Model::Subject)
        end

        lines
      end

      private

      def subject_names_for_query
        as_object_subject_names = []
        @model.subjects.each do |subject|
          subject.objects(reject_rdf_type: true).each do |object|
            case object
            when Model::Subject
              as_object_subject_names << object.name unless subject.name == object.name
            when Model::ValueList
              as_object_subject_names << object.value.select do |v|
                v.is_a?(Model::Subject) && subject.name != v.name
              end.map(&:name)
            end
          end
        end

        subject_names = @model.subjects.map(&:name) - as_object_subject_names.flatten.uniq
        subject_names = [@model.subjects.first.name] if subject_names.empty?

        subject_names
      end

      def subject_value(subject)
        if subject.value =~ /\A<.+>\z/
          subject.value[1..-2]
        else
          prefix, local_part = subject.value.split(':', 2)
          "#{@prefix[prefix].to_s[1..-2]}#{local_part}"
        end
      end

      def skip_object?(object)
        (object.is_a?(Model::Subject) && object.name == current_subject.name) ||
          (object.is_a?(Model::ValueList) && object.value.select { |v| v.is_a?(Model::Subject) }.size > 1)
      end

      def indent
        INDENT * depth
      end

      def depth
        @subjects.size
      end

      def current_subject
        if @subjects.size == 1
          @subjects.first
        else
          @subjects[-2]
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  params = ARGV.getopts('o:')
  output_dir = params['o']
  if output_dir && !File.exist?(output_dir)
    require 'fileutils'
    FileUtils.mkdir_p(output_dir)
  end

  config_dirs = ARGV
  config_dirs.each do |config_dir|
    puts "-- #{config_dir} --"
    begin
      config = RDFConfig::Config.new(config_dir)
      generator = RDFConfig::Grasp::QueryGenerator.new(config)
      query = generator.generate
      puts query
      next unless output_dir

      File.open(File.join(output_dir, "#{File.basename(config_dir)}.graphql"), 'w') do |f|
        f.puts query
      end
    rescue StandardError => e
      puts e
    end
  end
end

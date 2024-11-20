# frozen_string_literal: true

class RDFConfig
  class Validator
    attr_reader :errors, :warnings

    def initialize(config, **opts)
      @config = config
      @opts = opts

      @model = Model.instance(@config)

      @errors = []
      @warnings = []
    end

    def validate; end

    def valid?
      !error?
    end

    def error?
      !@errors.empty?
    end

    def warning?
      !@warnings.empty?
    end

    def puts_errors
      return if valid?

      warn @errors.join("\n")
    end

    def add_error(error)
      @errors << error
    end

    def add_warning(warning)
      @warnings << warning
    end

    private

    def model_subject_names
      @model_subject_names ||= @model.subject_names
    end

    def model_object_names
      @model_object_names ||= @model.object_names
    end

    def model_variable_names
      @model_variable_names ||= model_subject_names + model_object_names
    end
  end
end

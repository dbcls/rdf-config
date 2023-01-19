require_relative '../model'
require_relative '../model/subject'
require_relative '../service'

class RDFConfig
  class Grasp
    class Base < Service
      def initialize(config, opts = {})
        super

        @subject = opts[:subject]
        @subject = @model.subjects.first unless @subject.is_a?(Model::Subject)

        @add_namespace = opts[:add_namespace]
      end
    end
  end
end

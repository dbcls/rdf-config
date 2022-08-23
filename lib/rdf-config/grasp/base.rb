require_relative '../../rdf-config/model'
require_relative '../../rdf-config/model/subject'
require_relative '../../rdf-config/service'

class RDFConfig
  class Grasp
    class Base < Service
      def initialize(config, opts = {})
        super

        @subject = opts[:subject]
        @subject = @model.subjects.first unless @subject.is_a?(Model::Subject)
      end
    end
  end
end

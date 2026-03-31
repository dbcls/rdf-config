# frozen_string_literal: true

class RDFConfig
  class Convert
    module MixIn
      module JsonLdUtil
        def subject_name_by_node(node)
          node.keys.find { |name| model_subject_names.include?(name) }
        end

        def model_subject_names
          @model_subject_names ||= @model.subject_names
        end
      end
    end
  end
end

# frozen_string_literal: true

class RDFConfig
  class ModelGenerator
    module MixIn
      module NTriples
        def output_triples
          output_file_path = File.join(@output_dir,
                                       change_extension(File.basename(@input_file), '-triples.tsv'))
          # warn "output_file_path: #{output_file_path}"
          File.open(output_file_path, 'w') do |f|
            @triples.sort { |ta, tb| ta.first <=> tb.first }.each do |triple|
              f.puts [qname(triple[SUBJECT]), qname(triple[PREDICATE]), triple[OBJECT].map { |o| qname(o) }.join(',')].join("\t")
            end
          end
        end
      end
    end
  end
end

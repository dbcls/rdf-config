require 'rdf'

def lang(v, *args)
  RDF::Literal.new(v, language: args[0])
end

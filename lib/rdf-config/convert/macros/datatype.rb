require 'rdf'
require 'rdf/xsd'

def datatype(v, *args)
  case args[0]
  when 'xsd:date'
    RDF::Literal.new(v, datatype: RDF::XSD.date)
  when 'xsd:gYearMonth'
    RDF::Literal::YearMonth.new(v)
  else
    RDF::Literal.new(v, datatype: args[0])
  end
end

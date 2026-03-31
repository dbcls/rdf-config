# frozen_string_literal: true

require 'rdf'
require 'rdf/vocab'

def faldo_location(v, *args)
  begin_pos, end_pos = v.to_s.split('..')

  faldo = RDF::Vocabulary.new('http://biohackathon.org/resource/faldo#')

  graph = RDF::Graph.new

  location_bnode = RDF::Node.new
  graph << [location_bnode, RDF.type, faldo.Region]

  begin_bnode = RDF::Node.new
  graph << [location_bnode, faldo.begin, begin_bnode]
  graph << [begin_bnode, RDF.type, faldo.ExactPosition]
  graph << [begin_bnode, faldo.position, RDF::Literal::Integer.new(begin_pos)]

  end_bnode  = RDF::Node.new
  graph << [location_bnode, faldo.end, end_bnode]
  graph << [end_bnode, RDF.type, faldo.ExactPosition]
  graph << [end_bnode, faldo.position, RDF::Literal::Integer.new(end_pos)]

  graph
end

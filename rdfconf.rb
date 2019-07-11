require 'yaml'

class RDFconf

  attr_accessor :yaml

  def initialize(yaml)
    @yaml = YAML.load(yaml)
  end

  def schema(*args)
  end

  def stanza(*args)
  end

  # object of given predicates will be subjected to the text search index
  def search(*args)
  end

  def draw_schema_chart
  end

  def sparql_stanza
  end

  def sparql_search
  end

  def generate_shex
  end

end

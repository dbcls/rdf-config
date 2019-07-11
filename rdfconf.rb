require 'yaml'

class RDFconf

  attr_accessor :yaml

  def initialize(yaml)
    @yaml = YAML.load(yaml)
  end

  def schema
  end

  def indent(level)
    "    " * level
  end

  def senbero
    level = 0
    @yaml["subjects"].each do |subject, hash|
      attr = hash["attributes"]
      puts "<#{subject}> (#{attr['label']})"
      level += 1
      predicates = hash["predicates"]
      predicates.each do |predicate, hash|
        puts "#{indent(level)}|-- <#{predicate}>"
        object = hash["object"]
        puts "#{indent(level)}|       `-- <#{object['type']}> (#{object['example']})"
      end
      level -= 1
    end
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

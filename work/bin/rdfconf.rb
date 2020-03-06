require 'yaml'

class RDFconf

  attr_accessor :yaml

  def initialize(yaml)
    @yaml = YAML.load(yaml)
  end

  def schema
    # TODO: draw SVG or HTML/CSS diagram (as TogoStanza?)
  end

  def senbero
    subjects.each do |subject, hash|
      puts "#{subject} (#{subject_label(hash)})"
      predicates(hash).each do |predicate, hash|
        puts "    |-- #{predicate}"
        object = hash["object"]
        puts "    |       `-- #{object['type']} (#{object['example']})"
      end
    end
  end

  def stanza
    stanzas.each do |stanza, hash|
      puts "# #{stanza} #{endpoint}"
      puts
      prefixes.each do |prefix, uri|
        puts "PREFIX #{prefix}: <#{uri}>"
      end
      puts
      puts "SELECT *"
      graphs.each do |uri|
        puts "FROM <#{uri}>"
      end
      puts "WHERE {"
      variables(hash).each do |var, predicate|
        puts "  ?s #{predicate} ?#{var} ."
      end
      puts "}"
      puts
    end
  end

  def draw_schema_chart
  end

  def generate_stanza(*args)
  end

  def generate_shex
  end

  def sparql_search
  end

  # object of given predicates will be subjected to the text search index
  def search(*args)
  end

  private

  def endpoint
    @yaml["sparql"]["endpoint"]
  end

  def graphs
    @yaml["sparql"]["graphs"]
  end

  def prefixes
    @yaml["prefixes"]
  end

  def subjects
    @yaml["subjects"]
  end

  def attributes(hash)
    hash["attributes"]
  end

  def subject_label(hash)
    attributes(hash)["label"]
  end

  def subject_type(hash)
    attributes(hash)["type"]
  end
  
  def predicates(hash)
    hash["predicates"]
  end

  def stanzas
    @yaml["stanzas"]
  end

  def variables(hash)
    hash["variables"]
  end

end

#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'fileutils'
require 'open3'

class RDFConfig
  require 'rdf-config/model'
  require 'rdf-config/sparql'
  require 'rdf-config/stanza'
  require 'rdf-config/chart'

  def initialize(opts = {})
    @config_dir = opts[:config_dir]
    @model = Model.new(@config_dir)
    @opts = opts
  end

  def exec(opts)
    case opts[:mode]
    when :sparql
      puts generate_sparql
    when :query
      run_sparql
    when :stanza_rb
      generate_stanza_rb
    when :stanza_js
      generate_stanza_js
    when :senbero
      generate_senbero
    when :schema
      generate_schema
    end
  end

  def generate_sparql
    sparql = SPARQL.new(@model, @opts)
    sparql.generate
  end

  def run_sparql
    sparql = SPARQL.new(@model)
    sparql.run
  end

  def generate_stanza_rb
    stanza = Stanza::Ruby.new(@model, @opts)
    stanza.generate
  end

  def generate_stanza_js
    stanza = Stanza::JavaScript.new(@model, @opts)
    stanza.generate
  end

  def generate_schema
    schema = Chart::Schema.new(@model)
    schema.generate
  end

  def generate_senbero
    senbero = Chart::Senbero.new(@model)
    senbero.generate
  end
end



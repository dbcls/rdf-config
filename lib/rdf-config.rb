#!/usr/bin/env ruby

require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'fileutils'
require 'open3'

class RDFConfig
  require 'rdf-config/config'
  require 'rdf-config/model'
  require 'rdf-config/sparql'
  require 'rdf-config/stanza'
  require 'rdf-config/schema/senbero'
  require 'rdf-config/schema/chart'
  require 'rdf-config/grasp'
  require 'rdf-config/shex'

  def initialize(opts = {})
    @config = Config.new(opts[:config_dir])
    @opts = opts
  end

  def exec(opts)
    case opts[:mode]
    when :sparql
      puts generate_sparql
    when :sparql_url
      puts generate_sparql_url
    when :query
      run_sparql
    when :stanza_rb
      generate_stanza_rb
    when :stanza_js
      generate_stanza_js
    when :senbero
      generate_senbero
    when :chart
      generate_chart
    when :grasp
      generate_grasp
    when :shex
      puts generate_shex
    end
  end

  def generate_sparql
    sparql = SPARQL.new(@config, @opts)
    sparql.generate
  end

  def generate_sparql_url
    sparql = SPARQL.new(@config, @opts)
    sparql.generate(url_encode: true)
  end

  def run_sparql
    sparql = SPARQL.new(@model, @opts)
    sparql.run
  end

  def generate_stanza_rb
    stanza = Stanza::Ruby.new(@config, @opts)
    stanza.generate
  rescue Stanza::StanzaConfigNotFound, Stanza::StanzaExecutionFailure => e
    STDERR.puts e
  end

  def generate_stanza_js
    stanza = Stanza::JavaScript.new(@config, @opts)
    stanza.generate
  rescue Stanza::StanzaConfigNotFound, Stanza::StanzaExecutionFailure => e
    STDERR.puts e
  end

  def generate_senbero
    senbero = Schema::Senbero.new(@config)
    senbero.generate
  end

  def generate_chart
    schema = Schema::Chart.new(@config, @opts)
    schema.generate
  end

  def generate_grasp
    grasp = Grasp.new(@config)
    grasp.generate
  end

  def generate_shex
    shex = Shex.new(@config)
    shex.generate
  end
end

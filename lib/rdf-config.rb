#!/usr/bin/env ruby
# frozen_string_literal: true

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
    @config = if opts[:config_dir].is_a?(Array)
                opts[:config_dir].map { |config_dir| Config.new(config_dir) }
              else
                Config.new(opts[:config_dir])
              end
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
    if sparql.print_usage?
      sparql.print_usage
    else
      sparql.generate
    end
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
    warn e
  end

  def generate_stanza_js
    stanza = Stanza::JavaScript.new(@config, @opts)
    if stanza.sparql.print_usage?
      stanza.sparql.print_usage
    else
      stanza.generate
    end
  rescue Stanza::StanzaConfigNotFound, Stanza::StanzaExecutionFailure => e
    warn e
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

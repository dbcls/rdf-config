#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'json'
require 'uri'
require 'net/http'
require 'fileutils'
require 'open3'

require_relative 'rdf-config/config'
require_relative 'rdf-config/sparql'
require_relative 'rdf-config/stanza/javascript'
require_relative 'rdf-config/stanza/ruby'
require_relative 'rdf-config/schema/senbero'
require_relative 'rdf-config/schema/chart'
require_relative 'rdf-config/grasp'
require_relative 'rdf-config/shex'

class RDFConfig
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
      generate_sparql
    when :sparql_url
      generate_sparql_url
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
      generate_shex
    end
  end

  def generate_sparql
    sparql = SPARQL.new(@config, @opts)
    if sparql.print_usage?
      sparql.print_usage
    else
      puts sparql.generate
      sparql.print_warnings
    end
  end

  def generate_sparql_url
    sparql = SPARQL.new(@config, @opts)
    puts sparql.generate(url_encode: true)
    sparql.print_warnings
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
    if stanza.print_usage?
      stanza.print_usage
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
    grasp = Grasp.new(@config, @opts)
    grasp.generate
  end

  def generate_shex
    shex = Shex.new(@config)
    puts shex.generate
    shex.print_warnings
  end
end

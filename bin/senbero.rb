#!/usr/bin/env ruby

require 'getoptlong'
require './lib/rdf_config.rb'

opts = {
  :config_dir => '',
  :mode => '',
}

args = GetoptLong.new(
  [ '--config',   '-c',  GetoptLong::REQUIRED_ARGUMENT ],
  [ '--senbero',  '-l',  GetoptLong::NO_ARGUMENT ],
  [ '--schema',   '-f',  GetoptLong::NO_ARGUMENT ],
  [ '--sparql',   '-s',  GetoptLong::NO_ARGUMENT ],
  [ '--query',    '-q',  GetoptLong::NO_ARGUMENT ],
  [ '--stanza',   '-z',  GetoptLong::OPTIONAL_ARGUMENT ],
)

args.each_option do |name, value|
  case name
  when /--config/
    opts[:config_dir] = value
  when /--senbero/
    # FIX
    opts[:mode] = :senbero
  when /--schema/
    # TODO!!
    opts[:mode] = :schema
  when /--sparql/
    opts[:mode] = :sparql
  when /--query/
    # import https://gist.github.com/ktym/3385134
    opts[:mode] = :query
  when /--stanza/
    # re-use sparql.yaml instead of stanza.yaml
    case value
    when /ruby/i
      opts[:mode] = :stanza_rb
    else
      opts[:mode] = :stanza_js
    end
  else
    # show help
  end
end

rdf_config = RDFConfig.new(opts[:config_dir])
rdf_config.exec(opts[:mode])

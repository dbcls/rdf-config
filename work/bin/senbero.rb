#!/usr/bin/env ruby

require 'optparse'
load 'rdfconf.rb'

opts = ARGV.getopts('', 'schema', 'stanza', 'sparql')

yaml = File.read(ARGV.shift)

conf = RDFconf.new(yaml)

if opts["stanza"]
  conf.stanza
else
  conf.senbero
end




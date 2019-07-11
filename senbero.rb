#!/usr/bin/env ruby

load 'rdfconf.rb'

yaml = File.read(ARGV.shift)

conf = RDFconf.new(yaml)

#p conf
conf.senbero
#p conf.yaml["subject"]



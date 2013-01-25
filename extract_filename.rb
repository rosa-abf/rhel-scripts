#!/usr/bin/env ruby
# require 'rubygems';
require 'json';
require 'optparse'

sha1 = ''
OptionParser.new do |o|
  o.on('-s sha1') { |s| sha1 = s }
  o.parse!
end

results = %x[ curl -L http://file-store.rosalinux.ru/api/v1/file_stores?hash=#{sha1} ]
puts results == '[]' ? '' : JSON.parse(results).first['file_name']
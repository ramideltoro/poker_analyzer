#!/usr/bin/env ruby
# Import numerical category counts only. Matchup equities are deliberately excluded.
require 'csv'
require 'json'
require 'digest'
raw = ARGV.fetch(0)
rank = '23456789TJQKA'
canonical = lambda do |s|
  a,b = s[0,2].chars.sort_by { |c| -rank.index(c) }
  a+b+(a==b ? '' : s[-1])
end
categories=Hash.new { |h,k| h[k]=Array.new(9,0) }
boundaries=[1277,4137,4995,5853,5863,7140,7296,7452,7462]
rows=0; global=Array.new(9,0)
CSV.foreach(File.join(raw,'preflop-category.csv'),headers:true).with_index do |r,i|
  c=boundaries.index { |n| i<n }; abort('Unexpected rank row') unless c
  global[c]+=Integer(r['NoHand'])
  r.headers.drop(1).each { |s| categories[canonical.call(s)][c]+=Integer(r[s]) }
  rows+=1
end
abort('Invalid exhaustive reference') unless rows==7462 && categories.size==169 && categories.values.all? { |v| v.all? { |n| n>=0 } && v.sum==2_118_760 }
abort('Incorrect rank/category mapping') unless global==[23294460,58627800,31433400,6461620,6180020,4047644,3473184,224848,41584]
output={schema:1,source:'oscar6echo/Poker2',commit:'f4c46143a6f4504f2b2fe82da88dadec84f1c46a',boards:2_118_760,
  checksums:{'preflop-category.csv'=>Digest::SHA256.file(File.join(raw,'preflop-category.csv')).hexdigest},
  classes:categories.sort.to_h.transform_values { |v| {categories:v} }}
File.write(File.join(__dir__,'../Sources/PokerCore/Resources/preflop-reference.json'),JSON.pretty_generate(output)+"\n")
puts "Imported #{categories.size} classes; 2,118,760 category boards per class. No matchup equities imported."

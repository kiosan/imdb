$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'open-uri'
require 'net/http'
require 'rubygems'
require 'nokogiri'

require 'imdb/movie'
require 'imdb/person'

require 'imdb/movie_list'
require 'imdb/search'
require 'imdb/top_250'
require 'imdb/string_extensions'
require 'imdb/version'

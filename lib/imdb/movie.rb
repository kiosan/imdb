module Imdb

  # Represents a Movie on IMDB.com
  class Movie
    attr_accessor :id, :url, :title, :also_known_as

    # Initialize a new IMDB movie object with it's IMDB id (as a String)
    #
    #   movie = Imdb::Movie.new("0095016")
    #
    # Imdb::Movie objects are lazy loading, meaning that no HTTP request
    # will be performed when a new object is created. Only when you use an
    # accessor that needs the remote data, a HTTP request is made (once).
    #
    def initialize(imdb_id, title = nil, also_known_as = [])
      @id = imdb_id
      @url = "http://akas.imdb.com/title/tt#{imdb_id}/combined"
      @title = title.gsub(/"/, "") if title
      @also_known_as = also_known_as
    end

    def awards
      rows = awards_document.search('.awards table tr').select{ |n| n.search('td').count > 2 }
      result = rows.map do |row|
        elems = row.search('td')
        award = nil
        if elems.count == 3 && elems[0].search('b').count == 1
          type = elems[0]
          award = elems[1]
        elsif elems.count == 4 && elems[1].search('b').count == 1
          year = elems.first.inner_text.strip.to_i
          type = elems[1]
          award = elems[2]
        end
        {type: type.inner_text.strip.downcase, year: year, award: award.inner_text.strip} if award
      end
      result.compact!
    end

    def awards_document
      @awards_document ||= Nokogiri(open( "http://akas.imdb.com/title/tt#{@id}/awards"))
    end

    # Returns an array of cast members hashes
    def actors
      cast = []
      document.search("table.cast tr").each do |tr|
        member = {}
        tr.search("td.nm a") do |td|
          member[:person] = Person.new(td['href'].sub(%r{^/name/nm(.*)/}, '\1') )
        end
        member[:character] = tr.search("td.char a").inner_html.strip.imdb_unescape_html
        cast << member
      end
      cast
      rescue []
    end

    # Returns an array with cast members
    def cast_members
      document.search("table.cast td.nm a").map { |link| link.inner_html.strip.imdb_unescape_html } rescue []
    end

    def cast_member_ids
      document.search("table.cast td.nm a").map {|l| l['href'].sub(%r{^/name/nm(.*)/}, '\1') }
    end

    # Returns an array with cast characters
    def cast_characters
      document.search("table.cast td.char").map { |link| link.inner_text } rescue []
    end

    # Returns an array with cast members and characters
    def cast_members_characters(sep = '=>')
      memb_char = Array.new
      i = 0
      self.cast_members.each{|m|
        memb_char[i] = "#{self.cast_members[i]} #{sep} #{self.cast_characters[i]}"
        i=i+1
      }
      return memb_char
    end

    # Returns a array of the director hashes
    def directors
      directors = []
      directors_link = document.css("table a[name='directors']").first
      return directors unless directors_link
      directors_doc = document.css("table a[name='directors']").first.parent.parent.parent.parent
      directors_doc.search("a")[1..-1].each do |a|
        id = a['href'].sub(%r{^/name/nm(.*)/}, '\1')
        directors << Person.new(id)
      end
      directors

    end

    def writers
      writers = []
      writer_ids = []
      writers_link = document.css("table a[name='writers']").first
      return writers unless writers_link
      writers_doc = writers_link.parent.parent.parent.parent
      writers_doc.search("a")[1..-1].each do |a|
        id = a['href'].sub(%r{^/name/nm(.*)/}, '\1')
        if !writer_ids.include?(id) && !id.include?("/")
          writer_ids << id
          writers << Person.new(id)
        end
      end
      writers
    end

    def stars
      stars = []
      base_doc.search("div[itemprop='actors'] > a[itemprop='url']").each do |a|
        stars << Person.new(a['href'].sub(%r{^/name/nm(.*)/}, '\1'))
      end
      stars
    end


    # Returns the url to the "Watch a trailer" page
    def trailer_url
      'http://imdb.com' + document.at("a[@href*=/video/screenplay/]")["href"] rescue nil
    end

    # Returns an array of genres (as strings)
    def genres
      base_doc.search("span[itemprop='genre']").map { |link| link.inner_html.strip.imdb_unescape_html } rescue []
    end

    # Returns an array of languages as strings.
    def languages
      document.search("h5[text()='Language:'] ~ a[@href*='/language/']").map { |link| link.inner_html.strip.imdb_unescape_html } rescue []
    end

    # Returns an array of countries as strings.
    def countries
      document.search(".info  a[@href*='/country/']").map { |link| link.inner_html.strip.imdb_unescape_html } rescue []
    end

    # Returns the duration of the movie in minutes as an integer.
    def length
      document.search("//h5[text()='Runtime:']/..").inner_html[/\d+ min/].to_i rescue nil
    end

    # Returns a string containing the plot.
    def plot
      sanitize_plot(base_doc.search("p[itemprop='description']").first.inner_html.split("<a")[0].strip) rescue nil
    end

    # Returns a string containing the URL to the movie poster.
    def poster
      src = document.at("a[@name='poster'] img")['src'] rescue nil
      case src
      when /^(http:.+@@)/
        $1 + '.jpg'
      when /^(http:.+?)\.[^\/]+$/
        $1 + '.jpg'
      end
    end

    def keywords
      keywords_document.search("b.keyword a").map{ |link| link.inner_html.strip.imdb_unescape_html }
    end

    def other_titles
      res = release_document.search("#tn15content table")[1].search("tr td:first-child").map{|n| n.inner_html.strip.imdb_unescape_html }
      return [] if res[0].start_with?("<a")
      return res
    end

    def related_ids
      uri = URI("http://www.imdb.com/widget/recommendations/_ajax/get_more_recs?count=12&start=0&specs=p13nsims:tt#{id}&caller_name=p13nsims-title")

      req = Net::HTTP::Get.new(uri.request_uri)
      req['Host'] = 'www.imdb.com'
      req['Origin'] = 'http://www.imdb.com'
      req['Referer'] = 'http://www.imdb.com/title/tt0071562/'
      req['User-Agent'] = 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.95 Safari/537.11'

      res = Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(req)
      }
      recs = JSON.parse(res.body)
      recs["recommendations"].collect{|t| t["tconst"][-7..-1]}
    end

    # Returns a float containing the average user rating
    def rating
      document.at(".starbar-meta b").inner_html.strip.imdb_unescape_html.split('/').first.to_f rescue nil
    end

    # Returns an int containing the number of user ratings
    def votes
      document.at("#tn15rating .tn15more").inner_html.strip.imdb_unescape_html.gsub(/[^\d+]/, "").to_i rescue nil
    end

    # Returns a string containing the tagline
    def tagline
      document.search("h5[text()='Tagline:'] ~ div").first.inner_html.split("<a")[0].strip rescue nil
    end

    # Returns a string containing the mpaa rating and reason for rating
    def mpaa_rating
      document.search("h5[text()='MPAA:'] ~ div").first.inner_html.strip.imdb_unescape_html rescue nil
    end

    def mpaa_rating_code
      document.search("h5[text()='Certification:'] ~ div.info-content a[text()^='USA:']").first.inner_html.strip.imdb_unescape_html.gsub('USA:','') rescue nil
    end

    # Returns a string containing the title
    def title(force_refresh = false)
      if @title && !force_refresh
        @title
      else
        @title = document.at("h1").inner_html.split('<span').first.strip.imdb_unescape_html.gsub(/"/, "") rescue nil
      end
    end

    def episode_title
      document.at("h1 span em").inner_html.strip.imdb_unescape_html rescue nil
    end

    # Returns an integer containing the year (CCYY) the movie was released in.
    def year
      document.search('a[@href^="/year/"]').inner_html.to_i
    end

    # Returns release date for the movie.
    def release_date
      sanitize_release_date(document.search('h5[text()*=Release Date]').first.next_element.inner_html.to_s) rescue nil
    end



    # Returns a new Nokogiri document for parsing.
    def document
      @document ||= Nokogiri(Imdb::Movie.find_by_id(@id))
    end

    # Returns a new Nokogiri document for parsing.
    def keywords_document
      @keywords_document ||= Nokogiri(open("http://akas.imdb.com/title/tt#{@id}/keywords"))
    end

    # Returns a new Nokogiri document for parsing.
    def release_document
      @release_document ||= Nokogiri(open("http://akas.imdb.com/title/tt#{@id}/releaseinfo"))
    end



    # Use HTTParty to fetch the raw HTML for this movie.
    def self.find_by_id(imdb_id)
      open("http://akas.imdb.com/title/tt#{imdb_id}/combined")
    end

    # Use HTTParty to fetch the raw HTML for this movie.
    def self.find_base_by_id(imdb_id)
      open("http://akas.imdb.com/title/tt#{imdb_id}")
    end


    def base_doc
      @base_doc ||= Nokogiri(Imdb::Movie.find_base_by_id(@id))
    end

    # Convenience method for search
    def self.search(query)
      Imdb::Search.new(query).movies
    end

    def self.top_250
      Imdb::Top250.new.movies
    end

    def sanitize_plot(the_plot)
      the_plot = the_plot.imdb_strip_tags

      the_plot = the_plot.gsub(/add\ssummary|full\ssummary/i, "")
      the_plot = the_plot.gsub(/add\ssynopsis|full\ssynopsis/i, "")
      the_plot = the_plot.gsub(/&nbsp;|&raquo;/i, "")
      the_plot = the_plot.gsub(/see|more/i, "")
      the_plot = the_plot.gsub(/\|/i, "")

      the_plot = the_plot.strip.imdb_unescape_html
    end

    def sanitize_release_date(the_release_date)
      the_release_date = the_release_date.gsub(/<a.*a>/,"")
      the_release_date = the_release_date.gsub(/&nbsp;|&raquo;/i, "")
      the_release_date = the_release_date.gsub(/see|more/i, "")

      the_release_date = the_release_date.strip.imdb_unescape_html
    end

  end # Movie

end # Imdb

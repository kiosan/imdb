module Imdb
  class Person
    attr_accessor :id
    def initialize(imdb_id)
      @id = imdb_id
    end
    def name

      bio_document.at("h3[itemprop='name'] > a").inner_text
    end

    def real_name
      bio_document.at("h5[text()*='Birth Name']").next.inner_text.strip rescue nil
    end
    
    def birthdate
      Date.parse(bio_document.at("#overviewTable td[text()*='Date of Birth']").next_element.inner_text.split(",")[0]) rescue nil
    end
    
    def deathdate
      date_month = bio_document.at("h5[text()*='Date of Death']").next_element.inner_text.strip rescue ""
      year = bio_document.at("a[@href*='death_date']").inner_text.strip rescue ""
      Date.parse("#{date_month} #{year}") rescue nil
      
    end

    def nationality
      bio_document.at("a[@href*='birth_place']").inner_text.strip rescue nil
    end

    def height
      bio_document.at("h5[text()*='Height']").next.inner_text[/\(.+\)/] rescue nil
    end

    def biography
      bio_document.at("h5[text()*='Biography']").next_element.inner_text rescue nil
    end
    
    def photo
      photo_document.at("img#primary-img").get_attribute('src') if photo_document rescue nil
    end
    
    def filmography
      as_writer = main_document.at("#filmo-head-Writer").next_element.search('b a').map{|e| e.get_attribute('href')[/tt(\d+)/, 1] } rescue [] 
      as_actor = main_document.at("#filmo-head-Actor").next_element.search('b a').map{|e| e.get_attribute('href')[/tt(\d+)/, 1] } rescue [] 
      as_director = main_document.at("#filmo-head-Director").next_element.search('b a').map{|e| e.get_attribute('href')[/tt(\d+)/, 1] } rescue [] 
      as_composer = main_document.at("#filmo-head-Composer").next_element.search('b a').map{|e| e.get_attribute('href')[/tt(\d+)/, 1] } rescue [] 
      {writer: as_writer.map{|m| Movie.new(m)}, actor: as_actor.map{|m| Movie.new(m)}, director: as_director.map{|m| Movie.new(m)}, composer: as_composer.map{|m| Movie.new(m)} }
    end
    
    def main_document
      @main_document ||= Nokogiri open("http://www.imdb.com/name/nm#{@id}")
    end
    def bio_document
      @bio_document ||= Nokogiri open("http://www.imdb.com/name/nm#{@id}/bio")
    end
    
    def photo_document
      @photo_document ||= if photo_document_url then Nokogiri open("http://www.imdb.com" + photo_document_url) else nil end
    end
    
    def photo_document_url
      bio_document.at(".photo a[@name=headshot]").get_attribute('href') rescue nil
    end
    
  end
end
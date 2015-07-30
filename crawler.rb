#!/usr/bin/env ruby
# coding: utf-8

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'stringex'
require 'anemone'
require 'redis'
#require 'mongo'
require 'unicode' # Cyrillic caps support
require 'logger'
require 'art_typograph'
#require_relative 'colorize'


#---------------------------------------------------------------------------
#  Crawler settings
#---------------------------------------------------------------------------
SITE = 'http://www.site.com/'
# Content block to parse
CONTENT = '.content_block'
# Main image to parse
CONTENT_IMAGE = '.image_block'
CATEGORY = 'Category'
CATEGORY_RUS = 'Category_russian'
PATTERN = %r{.+}  # /.+/ - all
# Post_id count start from
post_id = 1


#---------------------------------------------------------------------------
#  Variables
#---------------------------------------------------------------------------
# publication date
# --  1 - after one day
# --  2 - after two days
day = 0.2
# number of file
file = 1
file_attach = 1
#
links = []
inc = 0
inc_link = 1
inc_attach = 1
links_found = 0
links_saved = 0
# paths
DOMAIN = URI.parse(SITE).host.gsub(/^www\./, '')
DATA_DIR = "#{DOMAIN}"
IMAGE_DIR = "#{DOMAIN}/images"
ATTACHMENT_DIR = "#{DOMAIN}/attach"
Dir.mkdir(DATA_DIR) unless File.exists?(DATA_DIR)
Dir.mkdir(IMAGE_DIR) unless File.exists?(IMAGE_DIR)
Dir.mkdir(ATTACHMENT_DIR) unless File.exists?(ATTACHMENT_DIR)
LINKS_OUT = "#{DATA_DIR}/links.txt"
#
$LOG = Logger.new("#{DATA_DIR}/parser.log", 'daily', 7)
#$LOG.level = Logger::ERROR


#---------------------------------------------------------------------------
#  Crawler options
#---------------------------------------------------------------------------
anemone_options = { 
                    :threads                => 8, 
                    :user_agent             => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9) AppleWebKit/537.35.1 (KHTML, like Gecko) Version/6.1 Safari/537.35.1', 
                    #:depth_limit           => 2000,
                    #:read_timeout          => 1,
                    :discard_page_bodies    => true,
                    :obey_robots_txt        => true
                }    # ----------  end crawler options  ----------


#---------------------------------------------------------------------------
#  Skip extensions
#---------------------------------------------------------------------------
ext = %w(flv swf png jpg gif asx zip rar tar 7z gz jar js css dtd xsd ico raw mp3 mp4 wav wmv ape aac ac3 wma aiff mpg mpeg avi mov ogg mkv mka asx asf mp2 m1v m3u f4v pdf doc xls ppt pps bin exe rss xml)


#---------------------------------------------------------------------------
#  Visual stylization
#---------------------------------------------------------------------------
class String
    def black;          "\033[30m#{self}\033[0m" end
    def red;            "\033[31m#{self}\033[0m" end
    def green;          "\033[32m#{self}\033[0m" end
    def yellow;         "\033[33m#{self}\033[0m" end
    def blue;           "\033[34m#{self}\033[0m" end
    def magenta;        "\033[35m#{self}\033[0m" end
    def cyan;           "\033[36m#{self}\033[0m" end
    def gray;           "\033[37m#{self}\033[0m" end

    def bg_black;       "\033[40m#{self}\033[0m" end
    def bg_red;         "\033[41m#{self}\033[0m" end
    def bg_green;       "\033[42m#{self}\033[0m" end
    def bg_brown;       "\033[43m#{self}\033[0m" end
    def bg_blue;        "\033[44m#{self}\033[0m" end
    def bg_magenta;     "\033[45m#{self}\033[0m" end
    def bg_cyan;        "\033[46m#{self}\033[0m" end
    def bg_gray;        "\033[47m#{self}\033[0m" end

    def bold;           "\033[1m#{self}\033[22m" end
    def reverse_color;  "\033[7m#{self}\033[27m" end
end    # ----------  end of colorize string  ----------

def loading
    chars = %w[| / ― \\]
    fps = 10
    delay = 1.0/fps

    fps.round.times do |i|
        print chars[ i % chars.length]
        sleep delay
        print "\b"
    end
end    # ----------  end of loading icon  ----------


#---------------------------------------------------------------------------
#  Helpers
#---------------------------------------------------------------------------
def time day = 0
    tn = Time.now + (60*60*24*day)
    tn.strftime("%Y-%m-%d %H:%M:%S")
end    # ----------  end of time helper  ----------

def time_gmt day = 0
    tn = Time.now.utc + (60*60*24*day)
    tn.strftime("%Y-%m-%d %H:%M:%S")
end    # ----------  end of time_gtm  ----------


#
# Get links from file
#
links.clear
File.open(LINKS_OUT, 'r').each_line { |l| links.push(l.gsub(/\n/,'')) } if File.exists?(LINKS_OUT)
links.compact.uniq
#
#
#


#---------------------------------------------------------------------------
#  Start
#---------------------------------------------------------------------------
time_start = Time.now
puts
puts " Start: #{time_start.strftime("%H:%M:%S")} ".black.bg_gray
$LOG.debug("Start: #{time_start.strftime("%H:%M:%S")}")
puts


#---------------------------------------------------------------------------
#  Crawling
#---------------------------------------------------------------------------
begin
  Anemone.crawl(SITE, options = anemone_options) do |ane|
    #ane.storage = Anemone::Storage.MongoDB
    ane.storage = Anemone::Storage.Redis
    ane.skip_links_like (/\.#{ext.join('|')}$/)

    ane.on_pages_like(PATTERN) do |page_url| #.on_every_page do |page| - without pattern
      print "#{links_found += 1}\t"
      case page_url.code
        when 200
          print "#{page_url.code}\t".green
        when 301
          print "#{page_url.code}\t".yellow
          $LOG.info "code #{page_url.code} - url #{page_url.url}"
        when 404
          print "#{page_url.code}\t".red
          $LOG.info "code #{page_url.code} - url #{page_url.url}"
        else
          print "#{page_url.code}\t"
        end # case
        puts page_url.url


      #---------------------------------------------------------------------------
      #  Parsing
      #---------------------------------------------------------------------------
      if (page_url.code == 200 && !page_url.doc.css(CONTENT).text.empty?)
        inc += 1
        day += 0.01
        day = day.round 2
        file += 1 if (inc % 400).zero? # 400 pages in 1 xml file
        file_attach += 1 if (inc_attach % 200).zero? # 200 images in 1 xml file
        
        post_id += 1 # (post id - article) + (post id - image)
        #
        loading
        print "day: #{day} file: #{file} attach: #{file_attach}\t saved links: #{inc_link}\t".gray
        if !links.include?(page_url.url)
            page_has_photo = false
            page = ''
            begin
              page = Nokogiri::HTML(open(page_url.url))
              #
              post_title = page.title()
              post_title = ArtTypograph.process(Unicode::capitalize(post_title), :use_p => false, :use_br => false, :entity_type => :no)
              
              post_content = page.css(CONTENT).text.strip.force_encoding("utf-8")

              if post_content.bytesize < 31_800 then # ArtTypograph limit ( max 32 kb )
                post_content = ArtTypograph.process(post_content, :use_p => false, :use_br => true, :entity_type => :no, :max_nobr => 2) << "\n"#:entity_type => :no, # :html, :xml, :no, :mixed
              end
              #
              post_creator = 'wordpress_user'
              post_date = time(day)
              post_date_gmt = time_gmt(day)
              post_comment_status = 'closed'
              post_ping_status = 'closed'
              post_url = post_title.to_url #thx - stringex (http://rubydoc.info/gems/stringex/2.1.2/frames)
              post_status = 'publish'
              post_parent = 0
              post_menu_order = 0
              post_type = 'post'
              post_seo_title = post_title
              if page.at("meta[name='description']")
                post_seo_desc = page.at("meta[name='description']")[:content].empty? ? 'custom_description' : Unicode::capitalize(page.at("meta[name='description']")[:content])
              end
              if page.at("meta[name='keywords']")
                post_seo_kw = page.at("meta[name='keywords']")[:content].empty? ? 'custom_keywords' : Unicode::downcase(page.at("meta[name='keywords']")[:content])
              end
              if page.at_css(CONTENT_IMAGE)
                node = page.at_css(CONTENT_IMAGE)
                uri = URI.parse(SITE).merge(URI.parse(node['src'])).to_s  # 'src' 'href'
                post_image_name = post_title.to_url + File.extname(uri)
                File.open("#{IMAGE_DIR}/#{post_image_name}",'wb'){ |f| f.write(open(uri).read) }
                print " -URL has image (.#{File.extname(uri)})- ".bg_green
                page_has_photo = true
              end

            rescue Exception => e
              print ":(\n".red
              puts "Error: #{e}"
              $LOG.error "Error in parsing: #{e}"
              sleep 5
            else
              if !File.exists?("#{DATA_DIR}/#{DOMAIN}(#{file})-content.xml") then
              new_import = Nokogiri::XML::Builder.new( :encoding => 'UTF-8') do |xml|
                xml.rss( "xmlns:excerpt" => "http://wordpress.org/export/1.2/excerpt/", "xmlns:content" => "http://purl.org/rss/1.0/modules/content/", 
                  "xmlns:wfw" => "http://wellformedweb.org/CommentAPI/", "xmlns:dc" => "http://purl.org/dc/elements/1.1/", "xmlns:wp" => "http://wordpress.org/export/1.2/", "version" => "2.0") do
                  xml.channel do |ch|
                    ch.language 'ru-RU'
                    ch['wp'].wxr_version 1.2
                  end
                end
              end
              File.open("#{DATA_DIR}/#{DOMAIN}(#{file})-content.xml", 'w') { |f| f.write new_import.to_xml }
              end

              if !File.exists?("#{ATTACHMENT_DIR}/#{DOMAIN}(#{file_attach})-attach.xml") then
              new_import_attach = Nokogiri::XML::Builder.new( :encoding => 'UTF-8') do |xml|
                xml.rss( "xmlns:excerpt" => "http://wordpress.org/export/1.2/excerpt/", "xmlns:content" => "http://purl.org/rss/1.0/modules/content/", 
                  "xmlns:wfw" => "http://wellformedweb.org/CommentAPI/", "xmlns:dc" => "http://purl.org/dc/elements/1.1/", "xmlns:wp" => "http://wordpress.org/export/1.2/", "version" => "2.0") do
                  xml.channel do |ch|
                    ch.language 'ru-RU'
                    ch['wp'].wxr_version 1.2
                  end
                end
              end
              File.open("#{ATTACHMENT_DIR}/#{DOMAIN}(#{file_attach})-attach.xml", 'w') { |f| f.write new_import_attach.to_xml }
              end

              add_xml = Nokogiri::XML(File.read("#{DATA_DIR}/#{DOMAIN}(#{file})-content.xml"),&:noblanks)
              Nokogiri::XML::Builder.with(add_xml.at('//channel')) do |xml|
                xml.item do |item|
                  item.title post_title
                  item['dc'].creator {item.cdata post_creator}
                  item['content'].encoded {item.cdata post_content}
                  item['excerpt'].encoded {item.cdata ''}
                  item['wp'].post_date post_date
                  item['wp'].post_date_gmt post_date_gmt
                  item['wp'].comment_status post_comment_status
                  item['wp'].ping_status post_ping_status
                  item['wp'].post_name post_url
                  item['wp'].status post_status
                  item['wp'].post_parent post_parent
                  item['wp'].menu_order post_menu_order
                  item['wp'].post_type post_type
                  post_tag_domain = DOMAIN
                  item.category( 'domain' => 'category', 'nicename' => CATEGORY) {item.cdata CATEGORY_RUS}
                  item.category( 'domain' => 'post_tag', 'nicename' => post_tag_domain.gsub('.','-')) {item.cdata DOMAIN}

                  item['wp'].postmeta do |pm|
                    pm['wp'].meta_key 'source'
                    pm['wp'].meta_value {pm.cdata DOMAIN}
                  end

                  item['wp'].postmeta do |pm|
                    pm['wp'].meta_key '_yoast_wpseo_opengraph-description'
                    pm['wp'].meta_value {pm.cdata post_seo_desc}
                  end

                  item['wp'].postmeta do |pm|
                    pm['wp'].meta_key '_yoast_wpseo_metadesc'
                    pm['wp'].meta_value {pm.cdata post_seo_desc}
                  end

                  item['wp'].postmeta do |pm|
                    pm['wp'].meta_key '_yoast_wpseo_title'
                    pm['wp'].meta_value {pm.cdata post_seo_title}
                  end

                  item['wp'].postmeta do |pm|
                    pm['wp'].meta_key '_yoast_wpseo_metakeywords'
                    pm['wp'].meta_value {pm.cdata post_seo_kw}
                  end

                  if page_has_photo
                    item['wp'].postmeta do |pm|
                      pm['wp'].meta_key '_thumbnail_id'
                      pm['wp'].meta_value {pm.cdata post_id}
                    end # do
                  end # if

                end # do
              end # Nokogiri do add_xml
                
              # Attachment
              if page_has_photo             
                add_xml_attach = Nokogiri::XML(File.read("#{ATTACHMENT_DIR}/#{DOMAIN}(#{file_attach})-attach.xml"),&:noblanks)
                Nokogiri::XML::Builder.with(add_xml_attach.at('//channel')) do |xml|
                  
                    xml.item do |item|
                      item.title post_title
                      item['dc'].creator {item.cdata post_creator}
                      item['content'].encoded {item.cdata ''}
                      item['excerpt'].encoded {item.cdata ''}
                      item['wp'].post_date '2014-03-14 05:00:00'         # 2014-03-14 05:00:00
                      item['wp'].post_date_gmt '2014-03-14 01:00:00'     # 2014-03-14 01:00:00
                      item['wp'].comment_status post_comment_status
                      item['wp'].ping_status post_ping_status
                      item['wp'].post_name post_url
                      item['wp'].status post_status
                      item['wp'].post_parent post_parent
                      item['wp'].menu_order post_menu_order
                      item['wp'].post_id post_id
                      item['wp'].post_type 'attachment'
                      item['wp'].attachment_url "http://www.yoursite.me/import/#{IMAGE_DIR}/#{post_image_name}"

                      item['wp'].postmeta do |pm|
                        pm['wp'].meta_key '_yoast_wpseo_metadesc'
                        pm['wp'].meta_value {pm.cdata post_seo_desc}
                      end

                      item['wp'].postmeta do |pm|
                        pm['wp'].meta_key '_yoast_wpseo_title'
                        pm['wp'].meta_value {pm.cdata post_seo_title}
                      end

                      item['wp'].postmeta do |pm|
                        pm['wp'].meta_key '_yoast_wpseo_metakeywords'
                        pm['wp'].meta_value {pm.cdata "custom_image_keywords"}
                      end

                      item['wp'].postmeta do |pm|
                        pm['wp'].meta_key '_wp_attached_file'
                        pm['wp'].meta_value {pm.cdata post_image_name}
                      end

                      item['wp'].postmeta do |pm|
                        pm['wp'].meta_key '_wp_attachment_image_alt'
                        pm['wp'].meta_value {pm.cdata post_title}
                      end
                    end # do

                inc_attach += 1
                end # Nokogiri do add_xml_attachment


                File.open("#{ATTACHMENT_DIR}/#{DOMAIN}(#{file_attach})-attach.xml", 'w') { |file| file.write add_xml_attach.to_xml } rescue print " Error in writing /(#{file_attach})-attach.xml ".bg_red
              end # if page_has_photo

              File.open("#{DATA_DIR}/#{DOMAIN}(#{file})-content.xml", 'w') { |file| file.write add_xml.to_xml }
              print ' -- PARSED '.bg_green + "\n"
            ensure
              #sleep 1.0 + rand
            end # done: begin/rescue
        end # if links.include?
        #
        links.push page_url.url
        inc_link += 1
      end #rescue print ' -- BAD URL '.bg_red + "\n" #if (page_url.code == 200 && !page_url.doc.css(CONTENT).text.empty?)
    end #ane.on_pages_like(PATTERN) do
    
  ane.after_crawl { puts ' Parsing finished '.black.bg_gray }
  end # Anemone do
rescue Exception => e
  puts "Message: #{e}".red
  puts e.inspect
  puts e.backtrace
  $LOG.error "Error: #{e}"
  sleep 5
else
#
ensure
  loading
  links.compact.uniq
  links_saved = links.size
  File.delete(LINKS_OUT) if File.exists?(LINKS_OUT)
  links.each do |link|
    File.open(LINKS_OUT, 'a') { |file| file.puts link }
  end rescue puts "Path 'LINKS_OUT' - error".red
  puts
  puts ' Links saved to file '.bg_cyan
end # done: begin

finish_time = Time.now - time_start
finish_min, finish_sec = finish_time / 60, finish_time % 60
finish_min, finish_sec = (finish_min).floor, (finish_sec).floor

puts
puts "Start:\t #{time_start.strftime("%H:%M:%S")}"
puts "Finish:\t #{Time.now.strftime("%H:%M:%S")}"
puts

puts
puts "Links found: " + "#{links_found}".cyan
puts "Links saved: " + "#{links_saved}".cyan
puts
puts "- COMPLETED - \t #{finish_min}m:#{finish_sec}s ".black.bg_gray
puts

$LOG.info("Finish: #{Time.now.strftime("%H:%M:%S")}")
$LOG.info("Time: #{finish_min}m:#{finish_sec}s")
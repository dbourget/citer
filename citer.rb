#!/usr/bin/env ruby
require 'pstore'
require 'net/http'
require 'etc'
require 'json'
require 'awesome_print'
require 'optparse'
require 'uri'
require 'yaml'

Base_URL = "https://api.philpapers.org"
Config_file = Etc.getpwuid.dir + "/.citer-config.yaml"
# this tool uses two local databases:
# a) a local database for each project (taken from current working directory). this stores the most recently resolved REFs items in the project.
# b) a global database in the uver's home directory, storing all resolved REFs as well as bibliographic data for each PP id

# database class

def dbg(text)
	$stderr.puts text
end
def info(text)
	$stderr.puts text
end

class String
def black;          "\e[30m#{self}\e[0m" end
def red;            "\e[31m#{self}\e[0m" end
def green;          "\e[32m#{self}\e[0m" end
def brown;          "\e[33m#{self}\e[0m" end
def blue;           "\e[34m#{self}\e[0m" end
def magenta;        "\e[35m#{self}\e[0m" end
def cyan;           "\e[36m#{self}\e[0m" end
def gray;           "\e[37m#{self}\e[0m" end

def bg_black;       "\e[40m#{self}\e[0m" end
def bg_red;         "\e[41m#{self}\e[0m" end
def bg_green;       "\e[42m#{self}\e[0m" end
def bg_brown;       "\e[43m#{self}\e[0m" end
def bg_blue;        "\e[44m#{self}\e[0m" end
def bg_magenta;     "\e[45m#{self}\e[0m" end
def bg_cyan;        "\e[46m#{self}\e[0m" end
def bg_gray;        "\e[47m#{self}\e[0m" end

def bold;           "\e[1m#{self}\e[22m" end
def italic;         "\e[3m#{self}\e[23m" end
def underline;      "\e[4m#{self}\e[24m" end
def blink;          "\e[5m#{self}\e[25m" end
def reverse_color;  "\e[7m#{self}\e[27m" end
end

class DB
	def initialize(file)
		@store = PStore.new(file)
	end
	def get(key)
		@store.transaction(true) do
			return @store[key]	
		end
	end
	def set(key, value)
		@store.transaction(false) do
			@store[key] = value
		end
	end
	def has_key?(key)
		v = false
		@store.transaction(true) { @store.root? key }
	end
	def delete_cached(str)
		deleted_count = 0
		@store.transaction(false) {
			@store.roots.each { |key|
				val = @store[key]
				should_delete = false
				match_type = ""
				
				begin
					# Try as regex first - check key, and if it's a hash, check relevant fields
					if key =~ /#{str}/
						should_delete = true
						match_type = "key"
					elsif val.is_a?(Hash)
						# Check bibtex_id, bibtex content, and other searchable fields
						searchable_content = [
							val[:bibtex_id],
							val[:bibtex],
							val[:id],
							(val[:entry] && val[:entry][:title])
						].compact.join(" ")
						
						if searchable_content =~ /#{str}/
							should_delete = true
							match_type = "content"
						end
					end
				rescue RegexpError
					# If regex fails, fall back to literal string matching
					if key.include?(str)
						should_delete = true
						match_type = "key (literal)"
					elsif val.is_a?(Hash)
						searchable_content = [
							val[:bibtex_id],
							val[:bibtex],
							val[:id],
							(val[:entry] && val[:entry][:title])
						].compact.join(" ")
						
						if searchable_content.include?(str)
							should_delete = true
							match_type = "content (literal)"
						end
					end
				end
				
				if should_delete
					puts "Forgetting #{key} (matched via #{match_type})"
					@store.delete key
					deleted_count += 1
				end
			}
		}
		
		if deleted_count == 0
			puts "Warning: No entries found matching '#{str}'"
		else
			puts "Deleted #{deleted_count} entries matching '#{str}'"
		end
	end
end

class Citer
	

	def initialize
    init_config
		@bibdata = DB.new("#{@config["cacheRoot"]}/.pp-citer-bibdata.data")
		@matches = DB.new("#{@config["cacheRoot"]}/.pp-citer-matches.data")
	end

  def prepare(args, bibfile)
		@biblist = {}
		@match_log = []
		@queries = 0
		@args = args
		@bibfile = bibfile
  end

	def escape(r)
		if @args[:escape]
			r = "`#{r}`{=latex}"
		end
		r
	end

  def debug_cache(v)
    if @bibdata.has_key? v
      ap @bibdata.get v
    end
    if @matches.has_key? v
      ap @matches.get v
    end
  end

	def line(l)
		l.gsub!(/\@([A-Z\-]{1,7}(?:[0-9]{1,4})?)/) do |m|
			bibentry = find_by_id($1)
			format_cite(bibentry)
		end
		segments = l.split(/\@\[/)
		newsegments = []
		author_name_string = nil
		while segments.size > 1
			#$stderr.puts "outer".green
			#$stderr.puts segments.ai
			before = segments.shift
			after = segments.shift	
			inner_segs = after.split(/\]/)
			#$stderr.puts "inner".blue
			#$stderr.puts inner_segs.ai
#				$stderr.puts "Ill-formed citation brackets. You might have a newline character inside the bracket (that breaks things).".red
#				$stderr.puts before
#				
#				exit(1)
#			end
			# the second part (after close bracket) belongs to the next citation if any
			query = inner_segs.shift
			throw :ill_formed_citation_brackets if query.nil?

			context = nil
			if before =~ /[a-z][a-z]/i
				author_name_string = before
			end
			bibentry = find_by_query(author_name_string.clone, query)
			newsegments << "#{before}#{format_cite(bibentry)}"

			if inner_segs.size >= 1
				segments.unshift inner_segs.join "]"
			end
#			exit if query =~ /australian inferentialism/
		end
		l = newsegments.join + segments.shift unless newsegments.size == 0
#		l.gsub!(/^(.*)\@\[(.*?)\]/) do |m|
#			before = $1
#		 	bibentry = find_by_query($1, $2)
#			before + format_cite(bibentry)
#		end

		l
	end

	def find_by_id(id)
		@bibdata.has_key?(id) ? @bibdata.get(id) : add_or_update(id)
	end
	
	def format_cite(data)
		#dbg "Citation: #{data[:id]} => #{r}".green
		@biblist[data[:id]] ||= data
		if @args[:format] == "md"
			return data[:entry][:year]
		elsif @args[:format] == "bibtex"
      r = ""
      #special case of forthcoming item
      if (data[:entry][:year] =~ /coming/)
        r += "forthco"
      end
			r += "\\" + @args[:command] + "{#{data[:bibtex_id]}}"	
      return escape r
    else
      return "???"
		end
	end

	def find_by_query(before, query)
		# attempt to extract author names before the query		
		# string before
#		l.gsub!(/\@\[\Qquery\E\].*$

		# check cache
		#dbg "#{query}".red
		#dbg before
		before.gsub!(/[^\w'\-]/, " ")
		before.gsub!(/'s\s*$/,"")
		words = before.split(/\s+/).reverse
		names = []
		# take all words staring with cap
		words.each do |w|
			if w =~ /^[A-Z]/
				w.gsub!(/'s?$/,"")
				names << w
			else
				break
			end
		end
		name_str = names.reverse.join(" ")
		pp_query = "#{name_str} #{query}"
    #ap ["check pp query", pp_query]
		if @matches.has_key? pp_query
			eId = @matches.get pp_query
			data = find_by_id eId
			log_match pp_query, data
#			dbg "found in cache"
			return data
		end
		uri = Base_URL + "/s/" + URI.escape(pp_query) + "?format=data"
    parsed = ""
    begin
      results = get_uri(uri)
      parsed = JSON.parse results, symbolize_names: true
    rescue Exception => e
      puts "A problem occurred fetching the data for query \"#{pp_query}\". Maybe there are illegal characters in the query? Punctuation is not allowed.".red
    ensure
      if parsed.length == 0
        $stderr.puts "Could not find any match for query tag @[#{query}]. The generated search (taking context into account) was #{pp_query}.".red
        exit(1)
      end
    end
				
		entry = parsed[0]
		data = find_by_id entry[:id]
		log_match pp_query, data, before
		@matches.set pp_query, entry[:id]
		data
	end

	def delete_cached(str)
		@matches.delete_cached(str)
		@bibdata.delete_cached(str)
	end

	def delete_by_exact_id(id)
		if @bibdata.has_key?(id)
			entry = @bibdata.get(id)
			puts "Forgetting entry with PhilPapers ID: #{id}"
			if entry && entry[:bibtex_id]
				puts "  BibTeX ID: #{entry[:bibtex_id]}"
			end
			if entry && entry[:entry] && entry[:entry][:title]
				puts "  Title: #{entry[:entry][:title]}"
			end
			@bibdata.instance_variable_get(:@store).transaction(false) do
				@bibdata.instance_variable_get(:@store).delete(id)
			end
			puts "Entry deleted successfully."
		else
			puts "Warning: No entry found with PhilPapers ID '#{id}'"
		end
	end

	def view_database(filter_regex = nil)
		count = 0
		@bibdata.instance_variable_get(:@store).transaction(true) do
			@bibdata.instance_variable_get(:@store).roots.each do |key|
				entry = @bibdata.instance_variable_get(:@store)[key]
				next unless entry.is_a?(Hash) && entry[:bibtex]
				
				# Apply filter if provided
				if filter_regex
					bibtex_content = entry[:bibtex]
					entry_data = entry[:entry]
					searchable_text = "#{bibtex_content} #{entry_data[:title]} #{entry_data[:authors].join(' ')} #{entry_data[:year]}"
					next unless searchable_text.match(Regexp.new(filter_regex, Regexp::IGNORECASE))
				end
				
				puts "% PhilPapers ID: #{key}"
				puts "% BibTeX ID: #{entry[:bibtex_id]}" if entry[:bibtex_id]
				puts entry[:bibtex]
				puts ""  # Add blank line between entries
				count += 1
			end
		end
		
		puts "# Total entries displayed: #{count}"
	end

	def log_match(query, data, context = "(unavailable)")
		entry = data[:entry]
		t = "= Citation match:"
    t += "\n  Query string used: " + "#{query}".green
		t += "\n  Hit: " + "#{entry[:authors]} (#{entry[:year]}) #{entry[:title]}.".magenta
		@match_log << t
		info t
	end
	
	def flush_match_log
		File.open("pp-citer-matches.log", "w") { |f| f.puts @match_log.join("\n") }
		@match_log = []
	end

	def biblio() 
		r = []
		@biblist.each_value do |entry|
			#puts "adding to bibitex: #{entry[:bibtex]}"
			r << (@args[:format] == "md" ? format_text_cite(entry) : entry[:bibtex])
		end
    r.sort.join("\n")
	end

  def format_text_cite(entry)
    #ap entry
    entry = entry[:entry]
    c = ""
    aus = entry[:authors] #.map { |s| reverse_name(s) }
    if aus.size > 1
      l = aus.last
      others = aus[0..-2]
      c += "#{others.join("; ")} and #{l}"
    else
      c += aus.first
    end
    c += " (" + entry[:year] + "). "
    if entry[:type] == "book"
      c += "_#{entry[:title]}_"
    else
      c += '"' + entry[:title] + '"'
    end
    c += "." unless entry[:title] =~ /\?\!\.$/

    return "* " + c + " " + entry[:pubInfo] + "\n"
  end

  def reverse_name(string)
    list = string.split(/, /)
    "#{list[1]} #{list[0]}"
  end

	def get_entry(id)
		d = get_format(id, "data")
		parsed = JSON.parse d, symbolize_names: true
		# delete some big fields we dont need
		parsed[0].delete :categories
		parsed[0].delete :abstract
		parsed[0]
	end

	def add_or_update(id)
		
		entry_data = get_entry(id)
		bibtex = get_format(id, "bib")
		#extract the bibtex id
		bibtex =~ /\@\w+\{(.+),/
		bibtex_id = $1
		d = { 
			id: id,
			bibtex_id: bibtex_id,
			updated: Time.now,
			entry: entry_data,	
			bibtex: bibtex
		}

		info "Added to database: #{id}".red
		@bibdata.set(id, d)
		d

	end

	def get_format(id, format)
		@queries += 1
    get_uri(Base_URL + "/utils/single_entry.pl?format=#{format}&eId=#{id}")
	end

	def get_uri(uri)
		#if (@queries >= 10)
		#	info "Waiting a little bit to be nice to PP and avoid blacklisting"
		#	sleep 1
		#end
		uri += "&apiKey=#{@config["apiKey"]}&apiId=#{@config["apiId"]}"
    #puts "URL: #{uri}"
		res = Net::HTTP.get_response(URI.parse(uri))
		if res.is_a?(Net::HTTPSuccess)
			return res.body
		else
			$stderr.puts "Could not obtain entry data from index. The following error occurred: #{res.body} (code #{res.code})".red
			throw :pp_query_error
		end

	end

  def config_file_error
    puts "Error loading config file #{Config_file}"
    puts "This file should exist and be a valid YAML file with the following format:"
#    puts "Citer:"
    puts "apiId: [your api id, which for PP is your user id]"
    puts "apiKey: [your api key]"
    puts "cacheRoot: [location where citer's cache directories will be created. this should not be a volatile location like /tmp"
    exit
  end

  def init_config
    config_file_error unless File.file? Config_file
    config_file_content = File.read(Config_file)
    @config = YAML.load(config_file_content)
    config_file_error unless @config["apiId"] && @config["apiKey"]
  end


end

args = {
	format: 'bibtex',
	command: 'citeyear',
	style: 'apa'
}

opt_parser = OptionParser.new do |opts|

	opts.banner = "Usage: citer.rb [options]"

	opts.on("-iINFILE", "--in=INFILE", "The file to process (mandatory).") do |f|
		args[:in] = f
	end

	opts.on("-oOUTFILE", "--out=OUTPUT", "The file to output the modified text to. Defaults to standard output (print out to terminal).") do |f|
		args[:out] = f
	end
	opts.on("-fFORMAT", "--format=FORMAT", "How to format citations. Can be either 'md' or 'bibtex'. Defaults to bibtex.") do |f|
		args[:format] = f
	end
	opts.on("-sSTYLE", "--style=STYLE", "The bibtex style to use (e.g. 'apa'). Defaults to apa.") do |f|
		args[:style] = f
	end
	opts.on("-bBIBFILE", "--bibfile=BIBFILE", "The file to output the bibliography to. Defaults to the name of the input file with '.bib' appended. This is ony used by the BibTeX format. Don't specify the .bib part.") do |f|
		args[:bibfile] = f
	end
	opts.on("-xEXTRA", "--extra=EXTRA", "An optional bibtex file to be merged with the produced bibtex file.") do |f|
		args[:extra] = f
	end
	opts.on("-cCOMMAND", "--command=COMMAND", "BibTeX command to use. Only relevant when tex format is used. Defaults to citeyear. Don't use backlash character in front of command name.") do |f|
		args[:command] = f
	end
	opts.on("-e", "--escape", "Perform multimarkdown-style escaping on BibTeX commands. You need to use this if processing mmd files to be later rendered with LaTeX.") do 
		args[:escape] = true
	end
  opts.on("-dDELETE", "--delete=DELETE", "Forget any search query OR bibtex entry matching the specified string as a regular expression. Use a dot (.) to delete everything. All the data will be refetched from PP as needed. This is useful if PP data have changed.") do |f|
		args[:forget] = f
	end
  opts.on("--delete-by-id=ID", "Delete entry with the exact PhilPapers ID specified.") do |f|
		args[:forget_by_id] = f
	end
  opts.on("-vSTR", "--view=STR","View the cached entry record or entry id for query STR.") do |v|
    citer = Citer.new
    citer.debug_cache(v)
    exit(0)
  end
  opts.on("--view-db", "View all entries in the bibdata database, printing the bibtex of each item.") do
    args[:view_db] = true
  end
  opts.on("--filter=REGEX", "When used with --view-db, filter entries matching the provided regular expression.") do |f|
    args[:filter] = f
  end
	
	opts.on("-h", "--help", "Prints this help") do
		puts opts
		exit
	end

end

citer = Citer.new

opt_parser.parse!
if args[:forget]
	citer.delete_cached(args[:forget])	
	exit(0)
end

if args[:forget_by_id]
	citer.delete_by_exact_id(args[:forget_by_id])	
	exit(0)
end

if args[:view_db]
	citer.view_database(args[:filter])
	exit(0)
end

if args[:in].nil? 
	puts opt_parser.help
	exit(1)
end 

file = args[:in]
info "Reading #{file}"
outfile = args[:out].nil? ? $stdout : File.open(args[:out], "w")
#info "Outputting to #{outfile.path}"
bibfile = outfile

citer.prepare(args, bibfile)
File.open(file).each do |line|
	outfile.puts citer.line(line).chomp
end

citer.flush_match_log

bibfilename = args[:bibfile] ||= "#{file}.bib"
if args[:format] == "bibtex"
	info "Saving bibliography to #{bibfilename}"
	bibfile = File.open(bibfilename, "w")
	if args[:extra]
		x = File.open(args[:extra], "r")
		bibfile.write(x.read)
	end
elsif args[:format] == "md"
  info "Saving bibliography to md format at the end of #{outfile.path}"
end

bibfile.puts "# Bibliography"
bibfile.puts citer.biblio


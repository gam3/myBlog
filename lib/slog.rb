require 'yaml'
require 'date'
require 'erb'
require 'rack'
require 'digest'
require 'open-uri'

if RUBY_PLATFORM =~ /win32/
  require 'maruku'
  Markdown = Maruku
else
  # require 'rdiscount'
  require 'redcarpet'
  # Markdown = Kramdown::Document
end

require 'builder'

require 'pp'

$LOAD_PATH.unshift File.dirname(__FILE__)

require 'ext/ext'

module Slog
  PATHS = {
    :templates => "templates",
    :pages => "templates/pages",
    :articles => "articles"
  }.freeze

  def self.env
    ENV['RACK_ENV'] || 'production'
  end

  def self.env=(env)
    ENV['RACK_ENV'] = env
  end

  module Template
    def to_html(page, config, &blk)
      path = ([:layout, :repo].include?(page) ? PATHS[:templates] : PATHS[:pages])
      config[:to_html].call(path, page, binding)
    end

    def markdown(text)
      ret = nil
      if @config[:markdown]
        renderer = Redcarpet::Render::HTML.new(fenced_code_blocks: true)
        markdown =
          Redcarpet::Markdown.new(
            renderer,
            fenced_code_blocks: true,
            strikethrough: true,
            disable_indented_code_blocks: true
          )

        ret = markdown.render(text.to_s.strip)
      else
        ret = text.strip
      end
      ret
    end

    def respond_to_missing?
      true
    end

    def method_missing(m, *args, &blk)
      keys.include?(m) ? self[m] : super
    end

    def self.included(obj)
      obj.class_eval do
        define_method(obj.to_s.split('::').last.downcase) { self }
      end
    end
  end

  class Site
    def initialize(config)
      @config = config
    end

    def [](*args)
      @config[*args]
    end

    def []=(key, value)
      @config.set key, value
    end

    def index(type = :html)
      ordered_article = type == :html ? articles.reverse : articles
      { :articles => ordered_article.map do |article|
        Article.new article, @config
      end }.merge archives
    end

    def archives(filter = "")
      if articles.empty?
        entries = []
      else
        entries = articles.select { |a| filter !~ /^\d{4}/ || File.basename(a) =~ /^#{filter}/ }
                          .reverse.map { |article| Article.new article, @config }
      end

      { :archives => Archives.new(entries, @config) }
    end

    def article(route)
      Article.new("#{PATHS[:articles]}/#{route.join('-')}.#{self[:ext]}", @config).load
    end

    def /
      self[:root]
    end

    def go(route, env = {}, type = :html)
      route << self./ if route.empty?
      type = type =~ /html|xml|json/ ? type.to_sym : :html
      path = route.join('/')

      context = ->(data, page) { Context.new(data, @config, path, env).render(page, type) }

      body, status =
        if Context.new.respond_to?(:"to_#{type}")
          if route.first =~ /\d{4}/
            case route.size
            when 1..3
              context[archives(route * '-'), :archives]
            when 4
              context[article(route), :article]
            else http 400
            end
          elsif respond_to?(path)
            context[send(path, type), path.to_sym]
          elsif (repo = @config[:github][:repos].grep(/#{path}/).first) &&
                !@config[:github][:user].empty?
            context[Repo.new(repo, @config), :repo]
          else
            context[{}, path.to_sym]
          end
        else
          http 400
        end
    rescue Errno::ENOENT
      return :body => http(404).first, :type => :html, :status => 404
    else
      return :body => body || "", :type => type, :status => status || 200
    end

    protected

    def http(code)
      [@config[:error].call(code), code]
    end

    def articles
      self.class.articles self[:ext]
    end

    class << self
      protected

      def articles(ext)
        Dir["#{PATHS[:articles]}/*.#{ext}"].sort_by { |entry| File.basename(entry) }
      end
    end

    class Context
      include Template
      attr_reader :env

      def initialize(ctx = {}, config = {}, path = "/", env = {})
        @config  = config
        @context = ctx
        @path    = path
        @env     = env
        @articles = Site.articles(@config[:ext]).reverse.map do |a|
          Article.new(a, @config)
        end

        ctx.each do |k, v|
          meta_def(k) { ctx.instance_of?(Hash) ? v : ctx.send(k) }
        end
      end

      def title
        @config[:title]
      end

      def render(page, type)
        content = to_html page, @config
        type == :html ? to_html(:layout, @config, proc { content }) : send(:"to_#{type}", page)
      end

      def to_xml(page)
        # Builder::XmlMarkup.new(:indent => 2)
        instance_eval File.read("#{PATHS[:templates]}/#{page}.builder")
      end
      alias :to_atom to_xml

      def respond_to_missing?
        true
      end

      def method_missing(m, *args, &blk)
        @context.respond_to?(m) ? @context.send(m, *args, &blk) : super
      end
    end
  end

  class Repo < Hash
    include Template

    README = "https://github.com/%s/%s/raw/master/README.%s".freeze

    def initialize(name, config)
      self[:name] = name
      @config = config
    end

    def readme
      markdown open(README.format([@config[:github][:user], self[:name], @config[:github][:ext]])).read
    rescue Timeout::Error, OpenURI::HTTPError
      "This page isn't available."
    end
    alias :content readme
  end

  class Archives < Array
    include Template

    def initialize(articles, config)
      replace articles
      @config = config
    end

    def [](a)
      a.is_a?(Range) ? self.class.new(slice(a) || [], @config) : super
    end

    def to_html
      super(:archives, @config)
    end
    alias :to_s to_html
    alias :archive archives
  end

  class Article < Hash
    include Template

    def initialize(obj, config = {})
      @obj = obj
      @config = config
      load if obj.is_a? Hash
    end

    def load
      data =
        if @obj.is_a? String
          begin
            meta, self[:body] = File.read(@obj).split(/\n\n/, 2)
          rescue => error
            STDERR.puts "THIS IS AN ERROR: \"#{error}\""
          end

          # use the date from the filename, or else toto won't find the article
          match = @obj.match(%r{/(\d{4}-\d{2}-\d{2})[^/]*$})
          (match[1] ? { :date => match[1] } : {}).merge(YAML.load(meta))
        elsif @obj.is_a? Hash
          @obj
        end.inject({}) { |h, (k, v)| h.merge(k.to_sym => v) }

      taint
      update data
      begin
        self[:date] = Date.parse(self[:date].tr('/', '-'))
      rescue
        Date.today
      end
      self
    end

    def [](key)
      load unless tainted?
      super
    end

    def slug
      self[:slug] || self[:title].slugize
    end

    def summary(length = nil)
      config = @config[:summary]
      sum =
        if self[:body] =~ config[:delim]
          self[:body].split(config[:delim]).first
        else
          self[:body].match(/(.{1,#{length || config[:length] || config[:max]}}.*?)(\n|\Z)/m).to_s
        end
      markdown(sum.length == self[:body].length ? sum : sum.strip.sub(/\.\Z/, '&hellip;'))
    end

    def url
      "http://#{(@config[:url].sub('http://', '') + path).squeeze('/')}"
    end
    alias :permalink url

    def body
      markdown self[:body].sub(@config[:summary][:delim], '')
    rescue
      markdown self[:body]
    end

    def path
      "/#{@config[:prefix]}#{self[:date].strftime("/%Y/%m/%d/#{slug}/")}".squeeze('/')
    end

    def title
      self[:title] || "an article"
    end

    def date
      @config[:date].call(self[:date])
    end

    def author
      self[:author] || @config[:author]
    end

    def to_html
      load
      super(:article, @config)
    end

    alias :to_s to_html
  end

  class Config < Hash
    DEFAULTS = {
      :author => ENV['USER'],                                 # blog author
      :title => Dir.pwd.split('/').last,                      # site title
      :root => "index",                                       # site index
      :url => "http://127.0.0.1",                             # root URL of the site
      :prefix => "",                                          # common path prefix for the blog
      :date => ->(now) { now.strftime("%d/%m/%Y") },          # date function
      :markdown => Hash.new,                                  # use markdown
      :disqus => false,                                       # disqus name
      :summary => { :max => 150, :delim => /~\n/ },           # length of summary and delimiter
      :ext => 'txt',                                          # extension for articles
      :cache => 28_800,                                       # cache duration (seconds)
      :github => { :user => "", :repos => [], :ext => 'md' }, # Github username and list of repos
      :to_html => lambda do |path, page, ctx|                 # returns an html, from a path & context
        ERB.new(File.read("#{path}/#{page}.rhtml")).result(ctx)
      end,
      :error => lambda do |code|                              # The HTML for your error page
        "<font style='font-size:300%'>toto, we're not in Kansas anymore (#{code})</font>"
      end
    }.freeze

    def initialize(obj)
      update DEFAULTS
      update obj
    end

    def set(key, val = nil, &blk)
      if val.is_a? Hash
        self[key].update val
      else
        self[key] = block_given? ? blk : val
      end
    end
  end

  class Server
    attr_reader :config, :site

    def initialize(config = {}, &blk)
      @config = config.is_a?(Config) ? config : Config.new(config)
      @config.instance_eval(&blk) if block_given?
      @site = Slog::Site.new(@config)
    end

    def call(env)
      @request  = Rack::Request.new env
      @response = Rack::Response.new

      return [400, {}, []] unless @request.get?

      path, mime = @request.path_info.split('.')
      route = (path || '/').split('/').reject(&:empty?)

      response = @site.go(route, env, *(mime ? mime : []))

      @response.body = [response[:body]]
      @response['Content-Length'] = response[:body].length.to_s unless response[:body].empty?
      @response['Content-Type']   = Rack::Mime.mime_type(".#{response[:type]}")

      # Set http cache headers
      @response['Cache-Control'] =
        if Slog.env == 'production'
          "public, max-age=#{@config[:cache]}"
        else
          "no-cache, must-revalidate"
        end

      @response['ETag'] = %("#{Digest::SHA1.hexdigest(response[:body])}")

      @response.status = response[:status]
      @response.finish
    end
  end
end

__END__

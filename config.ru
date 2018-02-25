$LOAD_PATH.unshift File.join(File.expand_path(File.dirname(__FILE__)), 'lib')

require 'slog'

# Rack config
use Rack::Static, :urls => ['/css', '/js', '/images', '/favicon.ico'], :root => 'public'
use Rack::CommonLogger

use Rack::ShowExceptions if ENV['RACK_ENV'] == 'development'

#
# Create and configure a toto instance
#
toto = Slog::Server.new do
  # set :author,    ENV['USER']                               # blog author
  # set :title,     Dir.pwd.split('/').last                   # site title
  set :title, "Available's Add"
  # set :root,      "index"                                   # page to load on /
  # set :date, lambda { |now| now.strftime("%d/%m/%Y") }
  # set :markdown,  :smart
  set :disqus, false
  set :markdown, :fenced_code_blocks => true, :disable_indented_code_blocks => true
  # set :summary,   :max => 150, :delim => /~/
  # set :ext,       'txt'
  # set :cache,      28800
  set :date, ->(now) { now.strftime("%B #{now.day.ordinal} %Y") }
end

run toto

__END__

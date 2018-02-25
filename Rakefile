require 'toto'

@config = Toto::Config::Defaults

task :default => :new

desc 'Create a new article.'
task :new do
  title = ask('Title: ')
  slug = title.empty? ? nil : title.strip.slugize

  article = { 'title' => title, 'date' => Time.now.strftime('%d/%m/%Y') }.to_yaml
  article << "\n"
  article << "Once upon a time...\n\n"

  path = "#{Toto::Paths[:articles]}/#{Time.now.strftime('%Y-%m-%d')}#{'-' + slug if slug}.#{@config[:ext]}"

  if File.exist? path
    toto "I can't create the article, #{path} already exists."
  else
    File.open(path, 'w') do |file|
      file.write article
    end
    toto "an article was created for you at #{path}."
  end
end

desc "Publish my blog."
task :publish do
  toto "publishing your article(s)..."
  `./update`
end

def toto(msg)
  puts "\n  toto ~ #{msg}\n\n"
end

def ask(message)
  print message
  STDIN.gets.chomp
end
__END__

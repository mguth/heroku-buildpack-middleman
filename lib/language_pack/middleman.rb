require "fileutils"
require "language_pack"
require "language_pack/rack"

class LanguagePack::Middleman < LanguagePack::Rack

  def self.use?
    File.exist?("config.rb") && File.directory?('source')
  end

  def initialize(*args)
    super *args
    @has_gemfile = File.exist?("Gemfile")
  end

  # The command to be ran to build the static files.
  def build_files_command
    "middleman build"
  end

  # Where the files are expected.
  def output_path
    "build"
  end

  def name
    "Middleman"
  end

  # Hack: this is checked by build_bundler. If it's true, it discards
  # Gemfile.lock and rebuilds the lockfile. We want to do that if there's no
  # Gemfile, so let the build pretend that it needs a Gemfile.lock in that
  # case.
  def has_windows_gemfile_lock?
    return true unless @has_gemfile
    super
  end

  # Called when there is no Gemfile.
  def create_implicit_gemfile
    no_gemfile_warning
    File.open('Gemfile', 'w') { |f| f.write default_gemfile_contents }
    File.open('Gemfile.lock', 'w') { |f| f.write '' }
  end

  def no_gemfile_warning
    topic("Warning: No Gemfile was found")
    puts "Your project will be running Middleman 2. To use version 3+,"
    puts "make sure that your project has a Gemfile."
  end

  # Usually the default addons include the shared database, but in this case,
  # we don't need any addons by default.
  def default_addons
    []
  end

  def compile
    Dir.chdir(build_path)
    remove_vendor_bundle
    create_implicit_gemfile unless @has_gemfile
    install_ruby
    setup_language_pack_environment
    allow_git do
      install_language_pack_gems
      build_bundler
      create_implicit_config_ru
      install_binaries
      build_static_files
    end
  end

  def build_static_files
    log("build_static_files") do
      topic("Building #{name} site")
      require 'benchmark'
      time = Benchmark.realtime { pipe("env PATH=$PATH:bin bundle exec #{build_files_command} 2>&1") }
      if $?.success?
        puts "#{name} build completed (#{"%.2f" % time}s)"
      else
        error "#{name} build failed."
      end
    end
  end

  # This creates an implicit config.ru (Rackup) file in case the project didn't come with one.
  def create_implicit_config_ru
    unless File.exist?('config.ru')
      log("create_config_ru") do
        topic("Creating default config.ru for #{name}")
        File.open('config.ru', 'w') { |f| f.write config_ru_contents }
      end
    end
  end

  def default_gemfile_contents
    %[
      source 'https://rubygems.org'
      gem 'middleman', '~> 2.0'
    ].strip.gsub(/^ {6}/, '')
  end

  def config_ru_contents
    %[
      # Modified version of TryStatic, from rack-contrib
      # https://github.com/rack/rack-contrib/blob/master/lib/rack/contrib/try_static.rb

      # Serve static files under a `#{output_path}` directory:
      # - `/` will try to serve your `#{output_path}/index.html` file
      # - `/foo` will try to serve `#{output_path}/foo` or `#{output_path}/foo.html` in that order
      # - missing files will try to serve #{output_path}/404.html or a tiny default 404 page


      module Rack

        class TryStatic

          def initialize(app, options)
            @app = app
            @try = ['', *options.delete(:try)]
            @static = ::Rack::Static.new(lambda { [404, {}, []] }, options)
          end

          def call(env)
            orig_path = env['PATH_INFO']
            found = nil
            @try.each do |path|
              resp = @static.call(env.merge!({'PATH_INFO' => orig_path + path}))
              break if 404 != resp[0] && found = resp
            end
            found or @app.call(env.merge!('PATH_INFO' => orig_path))
          end
        end
      end

      use Rack::TryStatic, :root => "#{output_path}", :urls => %w[/], :try => ['.html', 'index.html', '/index.html']

      # Run your own Rack app here or use this one to serve 404 messages:
      run lambda{ |env|
        not_found_page = File.expand_path("../#{output_path}/404.html", __FILE__)
        if File.exist?(not_found_page)
          [ 404, { 'Content-Type'  => 'text/html'}, [File.read(not_found_page)] ]
        else
          [ 404, { 'Content-Type'  => 'text/html' }, ['404 - page not found'] ]
        end
      }
    ].strip.gsub(/^ {6}/, '')
  end

end

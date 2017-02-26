run "pgrep -f spring | xargs kill -9"

# GEMFILE
########################################
run "rm Gemfile"
file 'Gemfile', <<-RUBY
source 'https://rubygems.org'
ruby '#{RUBY_VERSION}'

gem 'rails', '#{Rails.version}'
gem 'puma'
gem 'pg'
gem 'figaro'
gem 'jbuilder', '~> 2.0'
gem 'devise'
gem 'redis'
gem 'pundit'

gem 'sass-rails'
gem 'jquery-rails'
gem 'uglifier'
gem 'bootstrap-sass'
gem 'font-awesome-sass'
gem 'simple_form'
gem 'autoprefixer-rails'

group :development, :test do
  gem 'binding_of_caller'
  gem 'better_errors'
  #{Rails.version >= "5" ? nil : "gem 'quiet_assets'"}
  gem 'pry-byebug'
  gem 'pry-rails'
  gem 'spring'
  #{Rails.version >= "5" ? "gem 'listen', '~> 3.0.5'" : nil}
  #{Rails.version >= "5" ? "gem 'spring-watcher-listen', '~> 2.0.0'" : nil}
end

#{Rails.version < "5" ? "gem 'rails_12factor', group: :production" : nil}
RUBY

# Ruby version
########################################
file ".ruby-version", RUBY_VERSION

# Procfile
########################################
file 'Procfile', <<-YAML
web: bundle exec puma -C config/puma.rb
YAML

# Spring conf file
########################################
inject_into_file 'config/spring.rb', before: ').each { |path| Spring.watch(path) }' do
  "  config/application.yml\n"
end

# Puma conf file
########################################
if Rails.version < "5"
  puma_file_content = <<-RUBY
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }.to_i

threads     threads_count, threads_count
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }
RUBY

  file 'config/puma.rb', puma_file_content, force: true
end

# Clevercloud conf file
########################################
file 'clevercloud/ruby.json', <<-EOF
{
  "deploy": {
    "env": "production",
    "rakegoals": ["assets:precompile", "db:migrate"],
    "static": "/public"
  }
}
EOF

# Database conf file
########################################
inside 'config' do
  database_conf = <<-EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default
  database: #{app_name}_development

test:
  <<: *default
  database: #{app_name}_test

production:
  adapter:  postgresql
  encoding: utf8
  poll:     10
  host:     <%= ENV['POSTGRESQL_ADDON_HOST'] %>
  port:     <%= ENV['POSTGRESQL_ADDON_PORT'] %>
  database: <%= ENV['POSTGRESQL_ADDON_DB'] %>
  username: <%= ENV['POSTGRESQL_ADDON_USER'] %>
  password: <%= ENV['POSTGRESQL_ADDON_PASSWORD'] %>
EOF
  file 'database.yml', database_conf, force: true
end

# Assets
########################################
run "rm -rf app/assets/stylesheets"
run "curl -L https://github.com/guillaumecabanel/rails-stylesheets/raw/master/rails-stylesheets.zip > stylesheets.zip"
run "unzip stylesheets.zip -d app/assets && rm stylesheets.zip && mv app/assets/rails-stylesheets app/assets/stylesheets"

run 'rm app/assets/javascripts/application.js'
file 'app/assets/javascripts/application.js', <<-JS
//= require jquery
//= require jquery_ujs
//= require bootstrap-sprockets
//= require_tree .
JS

# Dev environment
########################################
gsub_file('config/environments/development.rb', /config\.assets\.debug.*/, 'config.assets.debug = false')

# Layout
########################################
run 'rm app/views/layouts/application.html.erb'
file 'app/views/layouts/application.html.erb', <<-HTML
<!DOCTYPE html>
<html>
  <head>
    <title>TODO</title>
    <%= csrf_meta_tags %>
    <%= render 'shared/metatags' %>

    #{Rails.version >= "5" ? "<%= action_cable_meta_tag %>" : nil}
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1">
    <%= stylesheet_link_tag    'application', media: 'all' %>
  </head>
  <body>
    <%= render 'shared/flashes' %>
    <%= yield %>
    <%= javascript_include_tag 'application' %>
  </body>
</html>
HTML

file 'app/views/shared/_flashes.html.erb', <<-HTML
<% if notice %>
  <div class="alert alert-info alert-dismissible" role="alert">
    <button type="button" class="close" data-dismiss="alert" aria-label="Close"><span aria-hidden="true">&times;</span></button>
    <%= notice %>
  </div>
<% end %>
<% if alert %>
  <div class="alert alert-warning alert-dismissible" role="alert">
    <button type="button" class="close" data-dismiss="alert" aria-label="Close"><span aria-hidden="true">&times;</span></button>
    <%= alert %>
  </div>
<% end %>
HTML


# README
########################################
markdown_file_content = <<-MARKDOWN
# App title
Short description...
MARKDOWN
file 'README.md', markdown_file_content, force: true

# Generators
########################################
generators = <<-RUBY
  config.generators do |generate|
    generate.assets false
    generate.helper false
  end
RUBY

environment generators

# AFTER BUNDLE
########################################
after_bundle do
  # Generators: simple form + pages controller
  ########################################
  generate('simple_form:install', '--bootstrap')
  generate(:controller, 'pages', 'home', '--no-helper', '--no-assets', '--skip-routes')

  # Routes
  ########################################
  route "root to: 'pages#home'"

  # Git ignore
  ########################################
  run "rm .gitignore"
  file '.gitignore', <<-TXT
.bundle
.clever.json
log/*.log
tmp/**/*
tmp/*
*.swp
.DS_Store
public/assets
TXT

  # Devise install + user
  ########################################
  generate('devise:install')
  generate('devise', 'User')

  # Pundit + App controller with Pundit config
  ########################################
  generate('pundit:install')
  run 'rm app/controllers/application_controller.rb'
  file 'app/controllers/application_controller.rb', <<-RUBY
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :authenticate_user!
  include Pundit

  # Pundit: white-list approach.
  after_action :verify_authorized, except: :index, unless: :skip_pundit?
  after_action :verify_policy_scoped, only: :index, unless: :skip_pundit?

  # Uncomment when you *really understand* Pundit!
  # rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  # def user_not_authorized
  #   flash[:alert] = "You are not authorized to perform this action."
  #   redirect_to(root_path)
  # end

  private

  def skip_pundit?
    devise_controller? || params[:controller] =~ /(^(rails_)?admin)|(^pages$)/
  end
end
RUBY

  # migrate + devise views
  ########################################
  rake 'db:drop db:create db:migrate'
  generate('devise:views')

  # Pages Controller
  ########################################
  run 'rm app/controllers/pages_controller.rb'
  file 'app/controllers/pages_controller.rb', <<-RUBY
class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :home ]

  def home
  end
end
RUBY

  # Metatags
  ########################################
  file 'app/views/shared/_metatags.html.erb', <<-HTML
<meta name="description" content="<%= meta_description %>">

<!-- Facebook Open Graph data -->
<meta property="og:title" content="<%= meta_title %>" />
<meta property="og:type" content="website" />
<meta property="og:url" content="<%= request.original_url %>" />
<meta property="og:image" content="<%= image_url(meta_image) %>" />
<meta property="og:description" content="<%= meta_description %>" />
<meta property="og:site_name" content="<%= meta_title %>" />

<!-- Twitter Card data -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:site" content="<%= DEFAULT_META['twitter_account'] %>">
<meta name="twitter:title" content="<%= meta_title %>">
<meta name="twitter:description" content="<%= meta_description %>">
<meta name="twitter:creator" content="<%= DEFAULT_META['twitter_account'] %>">
<meta name="twitter:image:src" content="<%= image_url(meta_image) %>">

<!-- Google+ Schema.org markup -->
<meta itemprop="name" content="<%= meta_title %>">
<meta itemprop="description" content="<%= meta_description %>">
<meta itemprop="image" content="<%= image_url(meta_image) %>">
HTML

  file 'app/helpers/meta_tags_helper.rb', <<-RUBY
module MetaTagsHelper
  def meta_title
    content_for?(:meta_title) ? content_for(:meta_title) : DEFAULT_META['meta_title']
  end

  def meta_description
    content_for?(:meta_description) ? content_for(:meta_description) : DEFAULT_META['meta_description']
  end

  def meta_image
    content_for?(:meta_image) ? content_for(:meta_image) : DEFAULT_META['meta_image']
  end
end
RUBY

  file 'config/meta.yml', <<-YAML
# https://www.lewagon.com/blog/tuto-setup-metatags-rails
meta_title: "TODO"
meta_description: "TODO"
meta_image: "TODO" # image from app/assets/images/
twitter_account: "@TODO" # Needed for Twitter Cards
YAML

  run 'rm config/environment.rb'
file 'config/environment.rb', <<-RUBY
# Load the Rails application.
require_relative 'application'

# Initialize the Rails application.
Rails.application.initialize!

# Initialize default meta tags.
DEFAULT_META = YAML.load_file(Rails.root.join('config/meta.yml'))
RUBY


  # Environments
  ########################################
  environment 'config.action_mailer.default_url_options = { host: "http://localhost:3000" }', env: 'development'
  environment 'config.action_mailer.default_url_options = { host: "http://TODO_PUT_YOUR_DOMAIN_HERE" }', env: 'production'

  # Figaro
  ########################################
  run "bundle binstubs figaro"
  run "figaro install"

  inside 'config' do
    figaro_yml = <<-EOF
# Export to clever with this command:

# development:

production:
  SECRET_KEY_BASE: "#{SecureRandom.hex(64)}"
  # To get faster deploy, cache dependencies:
  # CACHE_DEPENDENCIES: "true"
EOF
    file 'application.yml', figaro_yml, force: true
  end

  # Git
  ########################################
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit with devise template and CleverCloud config.' }
end

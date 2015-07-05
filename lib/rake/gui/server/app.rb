require 'sinatra'
require 'haml'

configure do
  set :start_time, Time.now
end

def running_time
  (Time.mktime(0)+(Time.now-settings.start_time)).strftime("%H:%M:%S")
end

get '/' do
  redirect :dashboard
end

get '/about' do
  @page_name = 'About'
  @page_description = 'About this Application'
  @breadcrumb_fa = 'file'
  @breadcrumbs = [
    { text: 'About', url: '/about' }
  ]

  haml :about
end

get '/dashboard' do
  @page_name = 'Dashboard'
  @page_description = 'Statistics Overview'
  @breadcrumb_fa = 'dashboard'
  @breadcrumbs = [
      { text: 'Dashboard', url: '/dashboard' }
  ]

  haml :dashboard
end

get '/console' do
  @page_name = 'Console'
  @page_description = 'View Logs'
  @breadcrumb_fa = 'desktop'
  @breadcrumbs = [
    { text: 'Console', url: '/console' }
  ]

  haml :console
end

get %r{/console/(?<path>.*)/?} do
  path = params[:path].split('/')
  return path.inspect
end

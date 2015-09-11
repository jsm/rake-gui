require 'pathname'
require 'sinatra'
require 'haml'

require_relative 'helpers.rb'
require_relative 'render.rb'
require_relative 'lib/log_stream.rb'

include Render

raise 'Invalid Number of Arguments' if ARGV.size != 3
working_directory, host, port = ARGV

configure do
  set :start_time, Time.now
  set :working_directory, Pathname.new(working_directory)
  set :bind, host
  set :port, port
  set server: 'thin'
end

get '/' do
  redirect :dashboard
end

get '/about' do
  about_page
end

get '/configuration' do
  configuration_page(
    'Host' => settings.bind,
    'Port' => settings.port,
    'Working Directory' => settings.working_directory,
  )
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

get '/server_logs' do
  @page_name = 'Server Logs'
  @page_description = 'View Access and Error logs for the webserver'
  @breadcrumb_fa = 'server'
  @breadcrumbs = [
      { text: 'Server Logs', url: '/server_logs' }
  ]

  haml :server_logs
end

get '/server_access_stream', provides: 'text/event-stream' do
  stream :keep_open do |out|
    log_stream = LogStream.new(File.join(settings.working_directory, 'server.log'), out)
    out.callback { log_stream.close }
  end
end

get '/server_error_stream', provides: 'text/event-stream' do
  stream :keep_open do |out|
    log_stream = LogStream.new(File.join(settings.working_directory, 'server.err.log'), out)
    out.callback { log_stream.close }
  end
end

get '/console' do
  @console_path = ''
  @page_name = 'Console'
  @page_description = 'View Logs'
  @breadcrumb_fa = 'desktop'
  @breadcrumbs = [
    { text: 'Console', url: '/console' }
  ]

  haml :console
end

get '/stream', provides: 'text/event-stream' do
  stream :keep_open do |out|
    log_stream = LogStream.new(File.join(settings.working_directory, 'full.log'), out)
    out.callback { log_stream.close }
  end
end

get %r{/console/(?<path>.*)/?} do
  path = params[:path].split('/')

  @executor_id = params[:executor]

  @console_path = params[:path]
  @page_name = 'Console'
  @page_description = "Viewing logs for #{path.last}"
  @breadcrumb_fa = 'desktop'
  @breadcrumbs = [
    { text: 'Console', url: '/console' }
  ]
  url = '/console'
  path.each do |t|
    url = url + '/' + t
    @breadcrumbs << {
      text: t,
      url: url
    }
  end

  if @executor_id
    @log_url = "/stream/#{@console_path}?executor=#{@executor_id}"
  else
    @log_url = "/stream/#{@console_path}"
  end

  haml :task
end

get %r{/stream/(?<path>.*)/?}, provides: 'text/event-stream' do
  path = params[:path].split('/')
  executor_id = params[:executor]

  if executor_id
    output_file = Pathname.new(File.join(settings.working_directory, *path, "#{executor_id}.log"))
  else
    output_file = Pathname.new(File.join(settings.working_directory, *path, 'main.log'))
  end

  stream :keep_open do |out|
    log_stream = LogStream.new(output_file, out)
    out.callback { log_stream.close }
  end
end

get %r{/executors/(?<path>.*)/?} do
  path = params[:path].split('/')

  task_directory = Pathname.new(File.join(settings.working_directory, *path))
  @executors = get_executors(task_directory)

  haml :executors, layout: false
end

get %r{/subtasks/(?<path>.*)/?} do
  path = params[:path].split('/')

  task_directory = Pathname.new(File.join(settings.working_directory, *path))
  @subtasks = get_subtasks(task_directory)

  haml :subtasks, layout: false
end

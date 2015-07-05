require 'sinatra'
require 'haml'

get '/' do
  haml :index
end

get '/about' do
  haml :about
end

get %r{/console/(?<path>.*)/?} do
  path = params[:path].split('/')
  return path.inspect
end

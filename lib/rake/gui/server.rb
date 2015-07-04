require 'fileutils'
require 'socket'

class Rake::Gui::Server
  RUBY = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name']).
         sub(/.*\s.*/m, '"\&"')

  def initialize(working_directory, options={})
    host = options[:host] ? options[:host] : '127.0.0.1'
    port = options[:port] ? options[:port] : find_available_port(host)

    # Generate the log files
    server_log = File.join(working_directory, 'server.log')
    err_log = File.join(working_directory, 'server.err.log')
    FileUtils.touch(server_log)
    FileUtils.touch(err_log)

    # Get the app code path
    app = File.expand_path(File.join(File.dirname(__FILE__), 'server', 'app.rb'))

    # Start the server in a subprocess
    @process = spawn("#{RUBY} #{app} '#{working_directory}' '#{host}' '#{port}'",
                     :out => server_log,
                     :err => err_log)
    $stdout.puts "Started Rake GUI Server reading from #{working_directory}"
    $stdout.puts "Accessible from #{host}:#{port}"
    `open http://#{host}:#{port}`
  end

  def find_available_port(host)
    server = nil
    (6400..6499).each do |p|
      begin
        server = TCPServer.new(host, p)
        port = server.addr[1]
        server.close
        return port
      rescue Errno::EADDRINUSE
        next
      end
    end
    raise 'No available ports in range 6400..6499'
  end

  def wait
    Process.wait(@process)
  end

  def exit
    Process.kill('INT', @process)
    $stdout.puts 'Killed the GUI server. If this does not exit soon, the rake task is still running.'
  end
end

require 'fileutils'
require 'haml'
require_relative '../helpers.rb'

class LogStream
  def initialize(file_path, stream)
    FileUtils::mkdir_p File.dirname(file_path)
    FileUtils.touch(file_path) unless File.exist?(file_path)  # Create file if it doesn't exist
    @file = File.open(file_path,"r")
    @stream = stream
    @thread = Thread.new(@file, @stream) do |file, stream|
      loop do
        sleep 1
        stream << "data: " + Haml::Helpers.preserve(ansi_to_html(file.read) + "\n") + "\n\n"
      end
    end
  end

  def close
    @thread.exit
    @file.close
    @stream.close
  end
end

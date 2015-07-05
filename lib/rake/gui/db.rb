require 'fileutils'

module Rake::Gui
  module DB
    extend self

    def puts(*args)
      open(generate_storage_path, 'a') do |f|
        args.each do |arg|
          f << arg.to_s << "\n"
        end
      end
    end

    def print(*args)
      open(generate_storage_path, 'a') do |f|
        args.each do |arg|
          f << arg.to_s
        end
      end
    end

    def print_to_full_log(str)
      open(File.join(Rake::Gui.working_directory, 'full.log'), 'a') do |f|
        f << str
      end
    end

    def generate_storage_path
      if execution_id = Thread.current.execution_id
        filename = "#{execution_id}.log"
      else
        filename = 'main.log'
      end
      path = File.join(Rake::Gui.working_directory, *current_invocation_chain.to_a.reverse.map(&:to_s), filename)

      # Make it's directory if it doesn't exist yet
      FileUtils::mkdir_p File.dirname(path)
      return path
    end
  end
end


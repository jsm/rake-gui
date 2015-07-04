require_relative 'logging.rb'
module Rake::ShellExecutors
  include Rake::Logging

  $working_directory = {}

  PRINT_THROTTLE = 0.1
  class ShellExecutionException < StandardError ; end
  class BashExecutionException < ShellExecutionException ; end

  def self.output(str, state, options)
    # Make duplicates of the arguments so that they won't be mutated
    str, state, options = str.dup, state.dup, options.dup
    # Deterimine what to print
    to_print = ''
    if state[:newline]
      to_print << "\n#{Time.now.strftime('[%H:%M:%S]')} " + str unless options[:no_timestamp]
      to_print << "\n" + str if options[:no_timestamp]
      state[:newline] = false
    elsif state[:first]
      to_print << "\n" if LockedPrintQueue.prepend_newline?
      to_print << "#{Time.now.strftime('[%H:%M:%S]')} " + str unless options[:no_timestamp]
      to_print << str if options[:no_timestamp]
      state[:first] = false
    else
      to_print << str
    end


    state[:newline] = true if str == "\n"
    state[:first] = true if str == "\r"
    # If options are set to not display output, we display a dot for each newline or reset
    print '.' if ["\n", "\r"].include?(str) && !options[:display_output] &&!options[:quiet]

    state[:output] << to_print unless str == "\n"

    # Return the new state
    return state
  end

  def self.run_bash_command(cmd, options)
    # Keep track of printing state
    state = {
      :output => '',
      :newline => false,
      :first => true
    }

    exit_status = nil
    (options[:retries]+1).times do |i|
      # This array is for remembering a little bit of the output in order to catch a breakpoint
      input_arr=[]

      # Run a virtual shell, and return exit code
      ::PTY.spawn %Q{bash -o pipefail -c#{options[:login] ? 'l' : ''} "#{cmd.gsub('"', '\"').gsub('$', '\$')}"} do |r, w, pid|
        begin
          r.sync
          r.each_char do |c|
            state = Rake::ShellExecutors.output c, state, options
            # Only display output if flag is set
            if options[:display_output]
              print state[:output] unless state[:output].empty?
              state[:output].replace('')
            end
            if options[:breakpoints]
              input_arr << c
              input_arr.shift if input_arr.size > 10
              is_breakpoint = Array(options[:breakpoints]).any? { |w| input_arr.join("") =~ /#{w}/ }
              if is_breakpoint
                input_arr=[]
                user_input = STDIN.gets.strip
                w.puts user_input
              end
            end
          end
        rescue Errno::EIO => e
        rescue => e
          puts e.message
          puts 'Backtrace:'
          e.backtrace.each{|trace| puts trace}
        ensure
          if options[:display_output]
            print state[:output] unless state[:output].empty?
            state[:output].replace('')
            print if state[:newline]
          end
          exit_status = ::Process.wait2(pid).last.exitstatus
        end
      end

      # Re-run bash command and add output if it failed and we have more retries left
      if exit_status != 0 && options[:retries] > i
        # Build the Retry String
        plural = options[:retries]-1 > i
        retry_string = "Command '#{cmd}'\n"
        retry_string << "Failed on attempt #{i+1}. "
        retry_string << 'There '
        retry_string << (plural ? 'are' : 'is')
        retry_string << " #{options[:retries]-i} "
        retry_string << (plural ? 'retries' : 'retry')
        retry_string << ' left.'

        retry_notice = state[:newline] ? "\n" : ''
        state[:newline] = false
        retry_notice << retry_string.colorize(:red) << "\n"
        state = Rake::ShellExecutors.output(retry_notice, state, options)
        state[:first] = true
      # Otherwise, return the results
      else
        return {
          :output => state[:output],
          :status => exit_status,
        }
      end
    end
  end

  module DSLs
    def build_command(command_to_build, *flags)
      command = [command_to_build]
      flags.each do |flag|
        if flag[:param].present? && (flag[:condition].nil? || flag[:condition] == true)
          command << "#{ flag[:flag] } #{ Array(flag[:param]).collect{ |param| '"' << param << '"' }.join(" ") }"
        end
      end
      return command.join(" ")
    end

    def cwd(directory, &block)
      $working_directory[Thread.current.object_id] = directory
      yield
      $working_directory.delete(Thread.current.object_id)
      return nil
    end

    def cmd(*args)
      cmd = args.join(" ")

      # Change working directory if within a cwd block
      cmd = ["cd #{$working_directory[Thread.current.object_id]} &&", cmd].join(' ') if $working_directory[Thread.current.object_id]

      if $RAKE_DEBUG
        puts cmd.colorize(:magenta)
        return
      end
      sh cmd
      unless $?.success?
        LockedPrintQueue.release
        raise ShellExecutionException
      end
    end

    # Run command in bash
    def bash(*args)
      # Configure Options
      options = ::Hashie::Mash.new
      options.merge!(args.pop) if args.last.respond_to? :merge
      options.verbose = !options.quiet && (Rake.verbose || options.verbose)
      options.display_output = true if options.verbose
      options.retries ||= 0

      # Create the command
      cmd = args.join(" ")

      # Change working directory if within a cwd block
      cmd = ["cd #{$working_directory[Thread.current.object_id]} &&", cmd].join(' ') if $working_directory[Thread.current.object_id]

      # If RAKE_DEBUG is on, display the command but don't run it
      if $RAKE_DEBUG
        puts cmd.colorize(:magenta)
        return
      end

      # Run the command in bash
      result = Rake::ShellExecutors.run_bash_command(cmd, options)

      # Determine if it succeeded
      succeeded = result[:status] == 0

      # If it didn't succeed, we want to display the output. Unless we're already shoing output
      puts result[:output].colorize(:yellow) if !succeeded && !options.show_output && !options.rescue
      # If It didn't succeed, or verbose is on, we want to display the command the was run
      puts cmd.colorize(succeeded ? :green : :red) if (!succeeded && !options.rescue) || options.verbose

      # Determine whether or not to rescue
      rescuing = false
      # Rescue if options.rescue set to true
      if options.rescue == true
        rescuing = true
      # Rescue if options.rescue matches with the shell output
      elsif options.rescue.is_a?(String) || options.rescue.is_a?(Regexp)
        rescuing = true if result[:output].match options.rescue
      end

      # If the command didn't succeed, raise an error unless we're rescuing
      raise BashExecutionException unless succeeded || rescuing
      return succeeded
    end
  end
end

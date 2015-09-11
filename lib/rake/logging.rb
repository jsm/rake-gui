require 'active_support/ordered_hash'
require 'colorize'
require 'thread'
require 'set'

require_relative 'gui.rb'
require_relative 'gui/db.rb'

# Promise/Thread Safe Logging Library
module Rake::Logging
  # Flag to turn on output to help in debugging
  DEBUG=false

  module StdoutWrapper
    extend self

    def puts(*args)
      if Rake::Gui.active?
        args.each do |arg|
          Rake::Gui::DB.print_to_full_log(arg.to_s << "\n")
        end
      else
        $stdout.puts(*args)
      end
    end

    def print(*args)
      if Rake::Gui.active?
        Rake::Gui::DB.print_to_full_log(args.join.to_s)
      else
        $stdout.print(*args)
      end

    end
  end

  class PrintQueue

    def initialize
      @promise_newline = {}
      @queue = ActiveSupport::OrderedHash.new
      @locked_output = ''
      @main_newline = false
      @priority_newline = {}
      @retrospective_newline = {}
      @retrospective_queue_newline = {}
      super
    end

    # Wrapper on stdout
    def stdout
      $stdout.print "{s#{caller.first.split(':', 3)[1]}}" if DEBUG
      return StdoutWrapper
    end

    # Newline wrapper
    # When DEBUG mode is on, indicates the line number that is using a newline
    def newline
      str = "\n"
      str << "{l#{caller.first.split(':', 3)[1]}}" if DEBUG
      return str
    end

    def prepend_newline?
      # Prepend a newline if one of the following is true:
      # 1. We requested a newline for the main thread, and we are in the main thread.
      # 2. We requested a newline for the priority promise, and we are in the priority promise.
      # 3. The current promise has requested a newline
      if main_thread? && @main_newline
        @main_newline = false
        return true
      elsif priority_promise? && final_newline?
        cancel_priority_newline
        return true
      elsif self.newline?
        self.cancel_newline
        return true
      else
        return false
      end
    end

    # Puts string(s) in a Promise-Safe MAnner
    def puts(*args)
      # Build the proper string to print
      to_print = ''

      # Variable to keep track of whether or not we want to prepend a newline
      prepend_newline = prepend_newline?
      to_print << newline if prepend_newline

      # Print each argument on a newline
      to_print << args.map(&:to_s).join(newline)
      # Add a newline to the end
      to_print << newline

      # Print it
      self.print_or_queue(to_print, !prepend_newline)
    end

    # Print string(s) in a Promise-Safe Manner
    def print(*args)
      # Build the proper string to print
      to_print = ''

      # Join the arguments into one string
      to_print << args.map(&:to_s).join

      # Print it
      self.print_or_queue(to_print)

      # Request a newline on the next puts
      if main_thread?
        @main_newline = true
      elsif priority_promise?
        request_priority_newline
      else
        self.request_newline
      end
    end

    # Decide to print now, or queue for printing later
    def print_or_queue(str, possible_newline=false)
      # Create the promise queue for this promise
      @queue[Thread.current.promise] ||= { :output => '' }

      # If the parent promise has a queue, add this promise to it's children
      parent = Thread.current.promise.parent
      if @queue[parent]
        @queue[parent][:children] ||= []
        @queue[parent][:children] << Thread.current.promise
      end

      # Print string if we're in the main thread or the priority promise
      if main_thread? || priority_promise?
        # If this is our first call as a priority promise, flush our parent
        flush_parent unless @queue[Thread.current.promise][:priority]
        @queue[Thread.current.promise][:priority] = true

        flush_current

        # Indicators on thread for debugging
        $stdout.print "{M}" if main_thread? && DEBUG
        $stdout.print "{P}" if priority_promise? && DEBUG

        # Print the string
        stdout.print str

      # Otherwise, save string to print queue
      else
        # If we're saving to the print queue, we'll want to notify that we might retrospectively want a prepended newline
        request_retrospective_newline(Thread.current.promise) if possible_newline && @queue.fetch(Thread.current.promise)[:output].empty?
        @queue[Thread.current.promise][:output] << "{Q}" if DEBUG

        # Add to print queue
        @queue[Thread.current.promise][:output] << str
      end
    end

    # Queue Output for immediate printing on next flush
    def queue_output(str)
      return unless str

      # Check if we might want to retrospectively add a newline
      if cancel_retrospective_newline(Thread.current.promise)
        # We want to retrospective add a newline
        # If the locked_output is empty though, it's still too early to tell
        if @locked_output.empty?
          request_retrospective_newline
        # If the locked_output isn't empty, then we want a retrospective newline if we've requested one for the queue
        elsif cancel_retrospective_queue_newline
          @locked_output << newline
        end
      end

      # Queue up the output
      @locked_output << str
    end

    # Is there any queued output?
    def queued_output?
      return @locked_output.length > 0
    end

    # Empty and print the queued output
    def flush_output
      return false unless @locked_output.length > 0
      stdout.print @locked_output
      @locked_output.clear
      return true
    end

    def final_newline?
      case @final_source
      when :main then
        output = @main_newline
        @main_newline = false
      when :priority then
        output = cancel_priority_newline
      when Fixnum then
        output = cancel_newline(@final_source)
      when :retrospective_queue then
        output = cancel_retrospective_queue_newline
      else
        output = false
      end
      @final_source = nil
      return output
    end

    def flush_current
      # Print our thread-queued output
      if @queue.fetch(Thread.current.promise,{})[:output].present?
        stdout.print newline if cancel_retrospective_newline(Thread.current.promise)
        stdout.print @queue.fetch(Thread.current.promise, {}).delete(:output)
      end
    end

    def flush_parent(parent=Thread.current.promise.parent)
      # Print our parent-queued output
      if @queue.fetch(parent,{})[:output].present?
        if cancel_retrospective_newline && final_newline?
          stdout.print newline
          set_newline(true, parent)
        end
        $stdout.print "FLUSHPARENT:" if DEBUG
        stdout.print @queue.fetch(parent, {})[:output]
        @queue[parent][:output] = ''
        @final_source = parent
      end
    end

    # Mark Thread as finished, and print everything that can be safely printed
    def flush
      # If we're in the main thread, we don't need to do anything other than print a newline if one was requested
      if main_thread?
        if @main_newline
          stdout.print(newline)
          @main_newline = false
        end
        return
      # If we're in the priority promise, we can print our promise-queued output
      # We can also flush the pending output
      # AND we can print any output that's been queued by the next promise in line
      elsif priority_promise?
        request_priority_newline if final_newline?
        # Set the final newline
        @final_source = :priority

        # Save the parent promise
        parent = Thread.current.promise.parent

        # Get the next queued
        next_queued_promise, next_queued_output = next_queued

        flush_current

        # Either print parent-queued or flush pending
        if @queue[parent]
          flush_parent(parent)
        else
          # Flush the pending output
          if queued_output?
            # Print a newline if one was requsted retrospectively
            stdout.print newline if cancel_retrospective_newline && final_newline?
            $stdout.print "FLUSHPENDING:" if DEBUG
            self.flush_output
            @final_source = :retrospective_queue
          end
        end

        # Print & clear the next thread's queued output
        if next_queued_output && next_queued_output[:output].present?
          if next_queued_output && cancel_retrospective_newline(next_queued_promise) && final_newline?
            set_newline(true, next_queued_promise)
            stdout.print newline
          end
          $stdout.print "FLUSHNEXT:" if DEBUG
          stdout.print next_queued_output[:output]
          next_queued_output[:output] = ''
          @final_source = next_queued_promise
        end

        # Delete our place in the queue
        self.unqueue

        # If we're a child promise, request a newline for the next in the parent thread
        if @queue[parent]
          request_newline(parent) if final_newline?
          @final_source = parent
        elsif main_thread?(parent) && @queue.empty?
          @main_newline = final_newline?
          @final_source = :main
        end

      # If we're not in the main or priority promise, we can't print immideately, so we add our thread's output to pending
      else
        # Unless, we're a child promise, then add our promise's output to it's parent's output
        parent = Thread.current.promise.parent
        if parent_queue = @queue[parent]
          if cancel_newline(parent) && cancel_retrospective_newline(Thread.current.promise)
            if parent_queue[:output].present?
              parent_queue[:output] << newline
            else
              @queue[Thread.current.promise][:retrospective_newline] = true
            end
            request_retrospective_newline if cancel_retrospective_newline(Thread.current.promise)
          end
          parent_queue[:output] << @queue.fetch(Thread.current.promise, {}).fetch(:output, '')
        else
          self.queue_output @queue.fetch(Thread.current.promise, {}).fetch(:output, '')
          # If we requested a newline for the promise, request it retroactively, since the promise is finished.
          request_retrospective_queue_newline if newline?
        end

        # Delete our place in the queue
        self.unqueue
      end

      # Set parent's settings
      request_newline(Thread.current.promise.parent) if newline?
      request_priority_newline if cancel_priority_newline(Thread.current.promise)
      request_retrospective_newline if cancel_retrospective_newline(Thread.current.promise)
      request_retrospective_queue_newline if cancel_retrospective_queue_newline(Thread.current.promise)
    end

    # Print a final newline if necessary
    def finalize
      stdout.print newline if main_thread? && final_newline?
    end

    # Used to completely print the entire queue in the case of exceptions
    def release
      # Only do this as the main thread
      return unless main_thread?

      @queue.each do |promise, info|
        stdout.print info[:output]
      end
      @promise_newline.clear
      @queue.clear
    end

    def unqueue(promise=Thread.current.promise)
      # Delete our place in the queue
      @queue.delete(promise)
      parent = promise.parent
      if parent_queue = @queue[parent]
        parent_queue.fetch(:children, {}).delete(promise)
      end
    end

    def next_queued
      # If we're the first promise in queue, return the next promise in queue
      return [@queue.keys[1], @queue.values[1]] if @queue.first && @queue.first.first == Thread.current.promise

      # Otherwise, if we have a parent, return the sibling promise
      parent = Thread.current.promise.parent
      parent_queue = @queue.fetch(parent, {})
      return nil unless parent_queue[:siblings].present?
      return  parent_queue[:siblings][parent_queue[:siblings].index(Thread.current.promise)]
    end

    # Returns true if currently in the thread that instantiated the PrintQueue
    def main_thread?(thread=Thread.current)
      return thread.object_id == Thread.main
    end

    # Returns true if the queue is empty, or our thread has the first place in the queue
    def priority_promise?(promise=Thread.current.promise)
      return false if promise == nil
      # If queue is empty, nothing has been added yet, so we'll be the first to do so
      return true if @queue.empty?

      # Start at the top of the queue
      level = @queue.first
      loop do
        current_promise, current_queue = level

        # Return true if the current promise is the first in queue
        return true if current_promise == promise

        # Otherwise, recursively check if we might be the first child of the first in queue
        if current_queue[:children].present?
          first_child =  current_queue[:children].first
          level = [first_child, @queue[first_child]]
        else
          break
        end
      end

      # Return false if no match
      return false
    end

    # Returns true if the current promise has requested a newline
    def newline?(promise=Thread.current.promise)
      return @promise_newline[promise] == true
    end

    # Request a newline for the current promise
    def request_newline(promise=Thread.current.promise)
      return @promise_newline[promise] = true
    end

    # Request a newline for the current promise
    def set_newline(value, promise=Thread.current.promise)
      return @promise_newline[promise] = value == true
    end

    # Cancel any requests the current promise has made for a newline
    def cancel_newline(promise=Thread.current.promise)
      return @promise_newline.delete(promise)
    end

    [:priority, :retrospective, :retrospective_queue].each do |nl|
      define_method("#{nl}_newline?") do |promise=Thread.current.promise.parent|
        return instance_variable_get("@#{nl}_newline")[promise] == true
      end

      define_method("request_#{nl}_newline") do |promise=Thread.current.promise.parent|
        return instance_variable_get("@#{nl}_newline")[promise] = true
      end

      define_method("set_#{nl}_newline") do |value, promise=Thread.current.promise.parent|
        return instance_variable_get("@#{nl}_newline")[promise] = value == true
      end

      define_method("cancel_#{nl}_newline") do |promise=Thread.current.promise.parent|
        return instance_variable_get("@#{nl}_newline").delete(promise)
      end
    end
  end

  # A PrintQueue that can only be accessed one at a time
  module LockedPrintQueue
    @@wrapped_queue = PrintQueue.new
    @@lock = Mutex.new

    PrintQueue.instance_methods.each do |m|
      m = m.to_sym
      define_method(m) do |*args, &block|
        @@lock.synchronize do
          output = @@wrapped_queue.send(m, *args, &block)
          return output
        end
      end
    end

    # Make this into a singleton
    extend self
  end

  module DSLs

    def puts_override(*args)
      Rake::Gui::DB.puts(*args)
      LockedPrintQueue.puts(*args)
    end

    def print_override(*args)
      Rake::Gui::DB.print(*args)
      LockedPrintQueue.print(*args)
    end

    LEVEL_MAP = {
      log: :cyan,
      info: :green,
      warning: :yellow,
      debug: :magenta,
      error: :red,
    }

    # DSLs for logging output with different colors
    LEVEL_MAP.each do |level, color|
      define_method(level) do |text, style=:puts|
        if style == :print
          print_override text.colorize(color)
        else
          puts_override text.colorize(color)
        end
      end
    end

    # Override the debug method to not print if verbose is not on
    unless Rake.verbose
      def debug(text, style=:puts)
      end
    end
  end

  def self.flushing_block(&block)
    # Flush the Print Queue at the end of each iteration
    lambda do |*args|
      begin
        block.call(*args) if block
      ensure
        LockedPrintQueue.flush
      end
    end
  end
end

require 'active_support/ordered_hash'
require 'colorize'
require 'thread'
require 'set'

require_relative 'gui.rb'
require_relative 'gui/db.rb'

# Thread Safe Logging Library
module Rake::Logging
  # Flag to turn on output to help in debugging
  DEBUG=false

  class PrintQueue

    def initialize
      @thread_newline = {}
      @queue = ActiveSupport::OrderedHash.new
      @locked_output = ''
      @main_newline = false
      @priority_newline = {}
      @retrospective_newline = {}
      @retrospective_queue_newline = {}
      @main_thread = Thread.current.object_id
      super
    end

    # Wrapper on stdout
    def stdout
      $stdout.print "{s#{caller.first.split(':', 3)[1]}}" if DEBUG
      return $stdout
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
      # 2. We requested a newline for the priority thread, and we are in the priority thread.
      # 3. The current thread has requested a newline
      if main_thread? && @main_newline
        @main_newline = false
        return true
      elsif priority_thread? && final_newline?
        cancel_priority_newline
        return true
      elsif self.newline?
        self.cancel_newline
        return true
      else
        return false
      end
    end

    # Puts string(s) in a Thread-Safe MAnner
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

    # Print string(s) in a Thread-Safe Manner
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
      elsif priority_thread?
        request_priority_newline
      else
        self.request_newline
      end
    end

    # Decide to print now, or queue for printing later
    def print_or_queue(str, possible_newline=false)
      # Create the thread queue for this thread
      @queue[Thread.current.object_id] ||= { :output => '' }

      # If the parent thread has a queue, add this thread to it's children
      parent_id = Thread.current.parent.object_id
      if @queue[parent_id]
        @queue[parent_id][:children] ||= []
        @queue[parent_id][:children] << Thread.current.object_id
      end

      # Print string if we're in the main thread or the priority thread
      if main_thread? || priority_thread?
        # If this is our first call as a priority thread, flush our parent
        flush_parent unless @queue[Thread.current.object_id][:priority]
        @queue[Thread.current.object_id][:priority] = true

        flush_current

        # Indicators on thread for debugging
        $stdout.print "{M}" if main_thread? && DEBUG
        $stdout.print "{P}" if priority_thread? && DEBUG

        # Print the string
        stdout.print str

      # Otherwise, save string to print queue
      else
        # If we're saving to the print queue, we'll want to notify that we might retrospectively want a prepended newline
        request_retrospective_newline(Thread.current.object_id) if possible_newline && @queue.fetch(Thread.current.object_id)[:output].empty?
        @queue[Thread.current.object_id][:output] << "{Q}" if DEBUG

        # Add to print queue
        @queue[Thread.current.object_id][:output] << str
      end
    end

    # Queue Output for immediate printing on next flush
    def queue_output(str)
      return unless str

      # Check if we might want to retrospectively add a newline
      if cancel_retrospective_newline(Thread.current.object_id)
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
      if @queue.fetch(Thread.current.object_id,{})[:output].present?
        stdout.print newline if cancel_retrospective_newline(Thread.current.object_id)
        stdout.print @queue.fetch(Thread.current.object_id, {}).delete(:output)
      end
    end

    def flush_parent(parent_id=Thread.current.parent.object_id)
      # Print our parent-queued output
      if @queue.fetch(parent_id,{})[:output].present?
        if cancel_retrospective_newline && final_newline?
          stdout.print newline
          set_newline(true, parent_id)
        end
        $stdout.print "FLUSHPARENT:" if DEBUG
        stdout.print @queue.fetch(parent_id, {})[:output]
        @queue[parent_id][:output] = ''
        @final_source = parent_id
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
      # If we're in the priority thread, we can print our thread-queued output
      # We can also flush the pending output
      # AND we can print any output that's been queued by the next thread in line
      elsif priority_thread?
        request_priority_newline if final_newline?
        # Set the final newline
        @final_source = :priority

        # Save the parent thread id
        parent_id = Thread.current.parent.object_id

        # Get the next queued
        next_queued_id, next_queued_output = next_queued

        flush_current

        # Either print parent-queued or flush pending
        if @queue[parent_id]
          flush_parent(parent_id)
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
          if next_queued_output && cancel_retrospective_newline(next_queued_id) && final_newline?
            set_newline(true, next_queued_id)
            stdout.print newline
          end
          $stdout.print "FLUSHNEXT:" if DEBUG
          stdout.print next_queued_output[:output]
          next_queued_output[:output] = ''
          @final_source = next_queued_id
        end

        # Delete our place in the queue
        self.unqueue

        # If we're a child thread, request a newline for the next in the parent thread
        if @queue[parent_id]
          request_newline(parent_id) if final_newline?
          @final_source = parent_id
        elsif parent_id == @main_thread && @queue.empty?
          @main_newline = final_newline?
          @final_source = :main
        end

      # If we're not in the main or priority thread, we can't print immideately, so we add our thread's output to pending
      else
        # Unless, we're a child thread, then add our thread's output to it's parent's output
        parent_id = Thread.current.parent.object_id
        if parent_queue = @queue[parent_id]
          if cancel_newline(parent_id) && cancel_retrospective_newline(Thread.current.object_id)
            if parent_queue[:output].present?
              parent_queue[:output] << newline
            else
              @queue[Thread.current.object_id][:retrospective_newline] = true
            end
            request_retrospective_newline if cancel_retrospective_newline(Thread.current.object_id)
          end
          parent_queue[:output] << @queue.fetch(Thread.current.object_id, {}).fetch(:output, '')
        else
          self.queue_output @queue.fetch(Thread.current.object_id, {}).fetch(:output, '')
          # If we requested a newline for the thread, request it retroactively, since the thread is finished.
          request_retrospective_queue_newline if newline?
        end

        # Delete our place in the queue
        self.unqueue
      end

      # Set parent's settings
      request_newline(Thread.current.parent.object_id) if newline?
      request_priority_newline if cancel_priority_newline(Thread.current.object_id)
      request_retrospective_newline if cancel_retrospective_newline(Thread.current.object_id)
      request_retrospective_queue_newline if cancel_retrospective_queue_newline(Thread.current.object_id)
    end

    # Print a final newline if necessary
    def finalize
      stdout.print newline if main_thread? && final_newline?
    end

    # Used to completely print the entire queue in the case of exceptions
    def release
      # Only do this as the main thread
      return unless main_thread?

      @queue.each do |thread_id, info|
        stdout.print info[:output]
      end
      @thread_newline.clear
      @queue.clear
    end

    def unqueue(thread=Thread.current)
      # Delete our place in the queue
      @queue.delete(thread.object_id)
      parent_id = thread.parent.object_id
      if parent_queue = @queue[parent_id]
        parent_queue.fetch(:children, {}).delete(thread.object_id)
      end
    end

    def next_queued
      # If we're the first thread in queue, return the next thread in queue
      return [@queue.keys[1], @queue.values[1]] if @queue.first && @queue.first.first == Thread.current.object_id

      # Otherwise, if we have a parent, return the sibling thread
      parent_id = Thread.current.parent.object_id
      parent_queue = @queue.fetch(parent_id, {})
      return nil unless parent_queue[:siblings].present?
      return  parent_queue[:siblings][parent_queue[:siblings].index(Thread.current.object_id)]
    end

    # Returns true if currently in the thread that instantiated the PrintQueue
    def main_thread?(thread=Thread.current)
      return thread.object_id == @main_thread
    end

    # Returns true if the queue is empty, or our thread has the first place in the queue
    def priority_thread?(thread=Thread.current)
      return false if main_thread?(thread)
      # If queue is empty, nothing has been added yet, so we'll be the first to do so
      return true if @queue.empty?

      # Start at the top of the queue
      level = @queue.first
      loop do
        current_thread, current_queue = level

        # Return true if the current thread is the first in queue
        return true if current_thread == thread.object_id

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

    # Returns true if the current thread has requested a newline
    def newline?(thread_id=Thread.current.object_id)
      return @thread_newline[thread_id] == true
    end

    # Request a newline for the current thread
    def request_newline(thread_id=Thread.current.object_id)
      return @thread_newline[thread_id] = true
    end

    # Request a newline for the current thread
    def set_newline(value, thread_id=Thread.current.object_id)
      return @thread_newline[thread_id] = value == true
    end

    # Cancel any requests the current thread has made for a newline
    def cancel_newline(thread_id=Thread.current.object_id)
      return @thread_newline.delete(thread_id)
    end

    [:priority, :retrospective, :retrospective_queue].each do |nl|
      define_method("#{nl}_newline?") do |thread=Thread.current.parent.object_id|
        return instance_variable_get("@#{nl}_newline")[thread] == true
      end

      define_method("request_#{nl}_newline") do |thread=Thread.current.parent.object_id|
        return instance_variable_get("@#{nl}_newline")[thread] = true
      end

      define_method("set_#{nl}_newline") do |value, thread=Thread.current.parent.object_id|
        return instance_variable_get("@#{nl}_newline")[thread] = value == true
      end

      define_method("cancel_#{nl}_newline") do |thread=Thread.current.parent.object_id|
        return instance_variable_get("@#{nl}_newline").delete(thread)
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
      if Rake::Gui.active?
        Rake::Gui::DB.puts(*args)
      else
        LockedPrintQueue.puts(*args)
      end
    end

    def print_override(*args)
      if Rake::Gui.active?
        Rake::Gui::DB.print(*args)
      else
        LockedPrintQueue.print(*args)
      end
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

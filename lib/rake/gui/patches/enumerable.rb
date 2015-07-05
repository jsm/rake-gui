require_relative '../../logging.rb'

# Add some parallel iterators to Enumerable
module Enumerable
  # Defines Enumerable#parallel_each and Enumerable#parallel_map
  [:each, :map].each do |m|
    define_method("parallel_#{m}") do |options={}, &block|
      # Release in case there's leftover logs
      Rake::Logging::LockedPrintQueue.release

      # Variable for storing parallel output
      output = nil

      execution_id = options[:execution_id]

      # Have the block set an execution_id on launch
      new_block = lambda do |*args|
        if execution_id
          Thread.current.execution_id = execution_id
        else
          Thread.current.reset_execution_id
        end
        block.call(*args) if block
        Thread.current.clear_execution_id
      end

      begin # Execute in parallel
        futures = self.to_a.map do |item|
          Rake.application.thread_pool.future(item, &Rake::Logging.flushing_block(&new_block))
        end
        output = futures.send(m) { |f| f.value }
      rescue => e # Release on Error
        Rake::Logging::LockedPrintQueue.release
        raise e
      ensure # Resolve any outstanding requests
        Rake::Logging::LockedPrintQueue.finalize
      end

      return output
    end
  end
end

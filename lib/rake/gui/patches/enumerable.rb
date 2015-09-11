require_relative '../../logging.rb'

# Add some parallel iterators to Enumerable
module Enumerable
  # Defines Enumerable#parallel_each and Enumerable#parallel_map
  [:each, :map].each do |m|
    define_method("parallel_#{m}") do |options={}, &block|
      # Convert options hash to a mash
      options = ::Hashie::Mash.new(options)

      # Release in case there's leftover logs
      Rake::Logging::LockedPrintQueue.release

      execution_id = options[:execution_id]

      # Have the block set an execution_id on launch
      new_block = lambda do |*args|
        if execution_id
          Thread.current.execution_id = execution_id
        else
          Thread.current.reset_execution_id
        end
        begin
          Rake::Gui::DB.generate_storage_path
          block.call(*args) if block
          Rake::Gui::DB.record_successful_executor
        rescue => e
          Rake::Gui::DB.record_failed_executor
          raise e, e.message, e.backtrace
        end
        Thread.current.clear_execution_id
      end

      begin # Execute in parallel
        # Run in threads seperate from the main thread pool if using an explicit option
        if options.force.present? || options.unlimited
          thread_count = options.unlimited ? self.size : options.force
          # Create a seperate thread pool
          thread_pool = Rake::ThreadPool.new(thread_count)
        else
          # Otherwise, use the existing thread pool
          thread_pool = Rake.application.thread_pool
        end

        # Join the threads!
        futures = self.to_a.map do |item|
          thread_pool.future(item, &Rake::Logging.flushing_block(&new_block))
        end

        return futures.send(m) { |f| f.value }
      rescue => e # Release on Error
        Rake::Logging::LockedPrintQueue.release
        raise e
      ensure # Resolve any outstanding requests
        Rake::Logging::LockedPrintQueue.finalize
      end
    end
  end
end

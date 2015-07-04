# Class Override for Rake::Task
class ::Rake::Task
  # Save the original invoke_with_call_chain instance method
  alias_method "__invoke_with_call_chain__", "invoke_with_call_chain"

  # Override the invoke_with_call_chain instance method
  # Provides a thread-safe variable to access information about the currently invoked chain
  def invoke_with_call_chain(task_args, invocation_chain)
    old_chain = Thread.current.promise.invocation_chain
    new_chain = ::Rake::InvocationChain.append(self, invocation_chain)
    Thread.current.promise.invocation_chain = new_chain
    begin
      Rake::Gui::DB.generate_storage_path
      __invoke_with_call_chain__(task_args, invocation_chain)  # And call the original invocation
      Rake::Gui::DB.record_successful_task
    rescue => e
      Rake::Gui::DB.record_failed_task
      raise e, e.message, e.backtrace
    end
    Thread.current.promise.invocation_chain = old_chain
  end
end

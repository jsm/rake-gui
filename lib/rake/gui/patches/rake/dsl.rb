require_relative '../thread.rb'
require_relative '../../../logging.rb'
require_relative '../../../shell_executors.rb'

module Rake::DSL
  include Rake::Logging::DSLs
  include Rake::ShellExecutors::DSLs

  alias :puts :puts_override
  alias :print :print_override

  def current_invocation_chain
    promise = Thread.current.promise
    while promise
      return promise.invocation_chain if promise.invocation_chain
      promise = promise.parent
    end
  end
end


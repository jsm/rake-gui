require_relative '../thread.rb'
require_relative '../../../logging.rb'
require_relative '../../../shell_executors.rb'

module Rake::DSL
  include Rake::Logging::DSLs
  include Rake::ShellExecutors::DSLs

  alias :puts :puts_override
  alias :print :print_override

  def current_invocation_chain
    bottom_up_threads = ([Thread.current] + Thread.current.lineage.reverse)
    bottom_up_threads.each do |thread|
      return thread[:invocation_chain] if thread[:invocation_chain]
    end
  end
end


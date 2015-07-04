require_relative '../../../logging.rb'

module Rake::DSL
  include Rake::Logging::DSLs

  alias :puts :puts_override
  alias :print :print_override

  def current_invocation_chain
    Thread.current[:invocation_chain]
  end
end


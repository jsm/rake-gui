require 'colorize'

module Rake
  class Application
    def display_exception_message_details(ex) # :nodoc:
      colored_message = ex.message.colorize(:red)
      if ex.instance_of?(RuntimeError)
        trace colored_message
      else
        trace "#{ex.class.name}: #{colored_message}"
      end
    end

    def display_exception_backtrace(ex) # :nodoc:
      if options.backtrace
        trace ex.backtrace.join("\n").colorize(:yellow)
      else
        trace Backtrace.collapse(ex.backtrace).join("\n").colorize(:yellow)
      end
    end
  end
end

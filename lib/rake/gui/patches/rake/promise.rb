class Rake::Promise
  attr_accessor :invocation_chain
  attr_reader :parent

  # Create a promise to do the chore specified by the block.
  # Overrides by adding @parent
  def initialize(args, &block)
    @mutex = Mutex.new
    @result = NOT_SET
    @error = NOT_SET
    @args = args
    @block = block
    @invocation_chain = nil
    @parent = Thread.current.promise
  end

   alias_method "__chore__", "chore"

   # Properly set the parent thread
   def chore(*args, &block)
     old_promise = Thread.current.promise
     Thread.current.promise = self
     __chore__(*args, &block)
     Thread.current.promise = old_promise
   end

   class Fake
     attr_accessor :invocation_chain
     attr_reader :parent
     def initialize
       @invocation_chain = nil
       @parent = nil
     end
   end
end

require_relative 'rake/promise.rb'

# Thread class override
# Keep track of parents and lineage
class ::Thread
  EXECUTION_ID_LENGTH = 16

   def execution_id
     return self['execution_id']
   end

   def execution_id=
     return self['execution_id']
   end

   def clear_execution_id
     self['execution_id'] = nil
   end

   def reset_execution_id
     self['execution_id'] = rand(36**EXECUTION_ID_LENGTH).to_s(36)
   end

   def promise
     self['promise']
   end

   def promise=(promise)
     self['promise'] = promise
   end
end

Thread.main.promise = Rake::Promise::Fake.new

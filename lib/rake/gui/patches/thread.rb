# Thread class override
# Keep track of parents and lineage
class ::Thread
  EXECUTION_ID_LENGTH = 16

  # Access the meta class to override the class method
   class << self
     alias_method "__new__", "new"

     def new *a, &b
       parent = Thread.current

       __new__(*a) do |*a|
         Thread.current.lineage = parent.lineage + [parent]
         Thread.current.parent = parent
         b.call *a
       end
     end
   end

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

   def lineage
     self['lineage'] || []
   end

   def lineage=(lineage)
     self['lineage'] = lineage
   end

   def parent
     self['parent']
   end

   def parent=(parent)
     self['parent'] = parent
   end
end

# Thread class override
# Keep track of parents and lineage
class ::Thread
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

require 'haml'
require_relative 'render.rb'

class Snapshot
  include Render

  attr_accessor :layout

  def initialize(layout=true)
    @layout = layout
  end

  def haml(view, options={})
    options[:layout] = @layout if options[:layout].nil?

    if options[:layout]
      Haml::Engine.new(File.read("views/layout.haml")).render(dup_no_layout) do
        Haml::Engine.new(File.read("views/#{view}.haml")).render(self)
      end
    else
      Haml::Engine.new(File.read("views/#{view}.haml")).render(dup_no_layout)
    end
  end

  def dup_no_layout
    dup = self.dup
    dup.layout = false
    return dup
  end
end

snapshot = Snapshot.new
puts snapshot.about_page

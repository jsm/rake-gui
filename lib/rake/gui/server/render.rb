module Render

  def about_page
    @page_name = 'About'
    @page_description = 'About this Application'
    @breadcrumb_fa = 'file'
    @breadcrumbs = [
      { text: 'About', url: '/about' }
    ]

    haml :about
  end

  def configuration_page(configurations)
    @page_name = 'Configuration'
    @page_description = 'View GUI settings'
    @breadcrumb_fa = 'wrench'
    @breadcrumbs = [
      { text: 'Configuration', url: '/configuration' }
    ]
    @configurations = configurations

    haml :configuration
  end

  def dashboard_page
    @page_name = 'Dashboard'
    @page_description = 'Statistics Overview'
    @breadcrumb_fa = 'dashboard'
    @breadcrumbs = [
      { text: 'Dashboard', url: '/dashboard' }
    ]

    haml :dashboard
  end
end

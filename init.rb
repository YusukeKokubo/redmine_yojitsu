require 'redmine'
require_dependency 'yojitsu_version_patch'

Redmine::Plugin.register :redmine_yojitsu do
  name 'Redmine Yojitsu plugin'
  author 'Yusuke Kokubo'
  description 'to view different of estimate hours and spent hours by each project.'
  version '0.0.1'
  
  project_module :yojitsu do
    permission :view_yojitsu, {:yojitsu => :show}
  end

  menu :project_menu, :yojitsu, {:controller => 'yojitsu', :action => 'show'}, :caption => :yojitsu
end

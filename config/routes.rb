ActionController::Routing::Routes.draw do |map|

  map.connect 'yojitsu/:action/:id/:user_id', :controller => :yojitsu

end


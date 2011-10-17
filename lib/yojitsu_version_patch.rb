require_dependency 'version'

module Yojitsu
  module VersionPatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)
    end
  
    module ClassMethods
    end
  
    module InstanceMethods
      def initial_estimate
        stories.inject(0.0) do |s,i|
          next s unless i.initial_estimate
          s + i.initial_estimate
        end
      end
    end
  end
end

Version.send(:include, Yojitsu::VersionPatch) unless Version.included_modules.include? Yojitsu::VersionPatch

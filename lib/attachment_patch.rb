require_dependency 'attachment'

# Patches Redmine's Attachments dynamically. Adds method acts_as_searchable
module AttachmentPatch
  def self.included(base) # :nodoc:
    # Same as typing in the class
    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development

      #acts_as_searchable :columns => ['title', "#{table_name}.description"], :include => :project 
      acts_as_searchable :columns => ["#{table_name}.filename", "#{table_name}.description"],
            :date_column => "#{table_name}.created_on",
            :project_key => "#{Project.table_name}.id"
    end
  end
end

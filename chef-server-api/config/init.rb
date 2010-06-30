#
# ==== Standalone Chefserver configuration
#
# This configuration/environment file is only loaded by bin/slice, which can be
# used during development of the slice. It has no effect on this slice being
# loaded in a host application. To run your slice in standalone mode, just
# run 'slice' from its directory. The 'slice' command is very similar to
# the 'merb' command, and takes all the same options, including -i to drop
# into an irb session for example.
#
# The usual Merb configuration directives and init.rb setup methods apply,
# including use_orm and before_app_loads/after_app_loads.
#
# If you need need different configurations for different environments you can
# even create the specific environment file in config/environments/ just like
# in a regular Merb application.
#
# In fact, a slice is no different from a normal # Merb application - it only
# differs by the fact that seamlessly integrates into a so called 'host'
# application, which in turn can override or finetune the slice implementation
# code and views.
#

require 'merb-assets'
require 'merb-helpers'
require 'merb-param-protection'

require 'bunny'
require 'uuidtools'
require 'ohai'
require 'openssl'

require 'chef'
require 'chef/role'
require 'chef/data_bag'
require 'chef/data_bag_item'
require 'chef/api_client'
require 'chef/webui_user'
require 'chef/certificate'
require 'chef/data_bag'
require 'chef/data_bag_item'
require 'chef/cookbook_version'
require 'chef/sandbox'
require 'chef/checksum'

require 'mixlib/authentication'

Mixlib::Authentication::Log.logger = Ohai::Log.logger = Chef::Log.logger

# Only used for the error page when visiting with a browser...
use_template_engine :haml

Merb::Config.use do |c|
  c[:session_id_key] = '_chef_server_session_id'
  c[:session_secret_key]  = Chef::Config.manage_secret_key
  c[:session_store] = 'cookie'
  c[:exception_details] = true
  c[:reload_classes] = true
  c[:log_level] = Chef::Config[:log_level]
  if Chef::Config[:log_location].kind_of?(String)
    c[:log_file] = Chef::Config[:log_location]
  end
end

unless Merb::Config.environment == "test"
  # create the couch design docs for nodes, roles, and databags
  Chef::CouchDB.new.create_id_map
  Chef::Node.create_design_document
  Chef::Role.create_design_document
  Chef::DataBag.create_design_document
  Chef::ApiClient.create_design_document
  Chef::WebUIUser.create_design_document
  Chef::CookbookVersion.create_design_document
  Chef::Sandbox.create_design_document
  Chef::Checksum.create_design_document

  # Create the signing key and certificate
  Chef::Certificate.generate_signing_ca

  # Generate the validation key
  Chef::Certificate.gen_validation_key

  # Generate the Web UI Key
  Chef::Certificate.gen_validation_key(Chef::Config[:web_ui_client_name], Chef::Config[:web_ui_key], true)

  Chef::Log.info('Loading roles')
  Chef::Role.sync_from_disk_to_couchdb
end

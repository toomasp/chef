#
# Author:: AJ Christensen (<aj@opscode.com>)
# Copyright:: Copyright (c) 2008 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'chef/config'
require 'chef/exceptions'
require 'chef/log'
require 'mixlib/cli'

class Chef::Application
  include Mixlib::CLI

  def initialize
    super

    trap("TERM") do
      Chef::Application.fatal!("SIGTERM received, stopping", 1)
    end

    trap("INT") do
      Chef::Application.fatal!("SIGINT received, stopping", 2)
    end

    unless RUBY_PLATFORM =~ /mswin|mingw32|windows/
      trap("HUP") do
        Chef::Log.info("SIGHUP received, reconfiguring")
        reconfigure
      end
    end

    at_exit do
      # tear down the logger
    end

    # Always switch to a readable directory. Keeps subsequent Dir.chdir() {}
    # from failing due to permissions when launched as a less privileged user.
  end

  # Reconfigure the application. You'll want to override and super this method.
  def reconfigure
    configure_chef
    configure_logging
  end

  # Get this party started
  def run
    reconfigure
    setup_application
    run_application
  end

  # Parse the configuration file
  def configure_chef
    parse_options

    unless config[:config_file] && File.file?(config[:config_file])
      Chef::Log.warn("*****************************************")
      Chef::Log.warn("Can not find config file: #{config[:config_file]}, using defaults.")
      Chef::Log.warn("*****************************************")
    end

    Chef::Config.from_file(config[:config_file]) if !config[:config_file].nil? && File.exists?(config[:config_file]) && File.readable?(config[:config_file])
    Chef::Config.merge!(config)
  end

  # Initialize and configure the logger
  def configure_logging
    Chef::Log.init(Chef::Config[:log_location])
    Chef::Log.level = Chef::Config[:log_level]
  end

  # Called prior to starting the application, by the run method
  def setup_application
    raise Chef::Exceptions::Application, "#{self.to_s}: you must override setup_application"
  end

  # Actually run the application
  def run_application
    raise Chef::Exceptions::Application, "#{self.to_s}: you must override run_application"
  end

  class << self
    # Log a fatal error message to both STDERR and the Logger, exit the application
    def fatal!(msg, err = -1)
      STDERR.puts("FATAL: #{msg}")
      Chef::Log.fatal(msg)
      Process.exit err
    end

    def exit!(msg, err = -1)
      Chef::Log.debug(msg)
      Process.exit err
    end
  end

end

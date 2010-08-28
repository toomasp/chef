#
# Author:: Adam Jacob (<adam@opscode.com>)
# Author:: Tim Hinderliter (<tim@opscode.com>)
# Author:: Christopher Walters (<cw@opscode.com>)
# Copyright:: Copyright (c) 2008, 2010 Opscode, Inc.
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
#

require File.expand_path(File.join(File.dirname(__FILE__), "..", "spec_helper"))

require 'chef/run_context'
require 'chef/rest'

describe Chef::Client, "run" do
  before(:each) do
    # Fake data to identify the node
    @HOSTNAME = "hostname"
    @FQDN = "hostname.example.org"
    Chef::Config[:node_name] = @FQDN
    
    # Fake node
    @node = Chef::Node.new(@HOSTNAME)
    @node.name(@FQDN)
    @node[:platform] = "example-platform"
    @node[:platform_version] = "example-platform-1.0"
    
    @mock_ohai = {
      :fqdn => @FQDN,
      :hostname => @HOSTNAME,
      :platform => 'example-platform',
      :platform_version => 'example-platform',
      :data => {
      }
    }
    @mock_ohai.should_receive(:all_plugins).and_return(true)
    @mock_ohai.should_receive(:data).and_return(@mock_ohai[:data])
    Ohai::System.should_receive(:new).and_return(@mock_ohai)

    # --Client.sync_cookbooks -- downloads the list of cookbooks to sync
    #
    # after run, check proper mutation of node
    # e.g., node.automatic_attrs[:platform], node.automatic_attrs[:platform_version]
    Chef::Config.node_path(File.expand_path(File.join(CHEF_SPEC_DATA, "run_context", "nodes")))
    Chef::Config.cookbook_path(File.expand_path(File.join(CHEF_SPEC_DATA, "run_context", "cookbooks")))
  end
  
  it "should identify the node and run ohai, then register the client" do
    mock_chef_rest_for_node = OpenStruct.new({ })
    mock_chef_rest_for_client = OpenStruct.new({ })
    mock_couchdb = OpenStruct.new({ })

    Chef::CouchDB.stub(:new).and_return(mock_couchdb)

    # --Client.register
    #   Use a filename we're sure doesn't exist, so that the registration 
    #   code creates a new client.
    temp_client_key_file = Tempfile.new("chef_client_spec__client_key")
    temp_client_key_file.close
    FileUtils.rm(temp_client_key_file.path)
    Chef::Config[:client_key] = temp_client_key_file.path
    
    #   Client.register will register with the validation client name.
    Chef::REST.should_receive(:new).with(Chef::Config[:chef_server_url]).at_least(1).times.and_return(mock_chef_rest_for_node)
    Chef::REST.should_receive(:new).with(Chef::Config[:client_url], Chef::Config[:validation_client_name], Chef::Config[:validation_key]).and_return(mock_chef_rest_for_client)
    mock_chef_rest_for_client.should_receive(:register).with(@FQDN, Chef::Config[:client_key]).and_return(true)
    #   Client.register will then turn around create another
    #   Chef::REST object, this time with the client key it got from the
    #   previous step.
    Chef::REST.should_receive(:new).with(Chef::Config[:chef_server_url], @FQDN, Chef::Config[:client_key]).and_return(mock_chef_rest_for_node)
    
    # --Client.build_node
    #   looks up the node, which we will return, then later saves it.
    mock_chef_rest_for_node.should_receive(:get_rest).with("nodes/#{@FQDN}").and_return(@node)
    mock_chef_rest_for_node.should_receive(:put_rest).with("nodes/#{@FQDN}", @node).exactly(2).times.and_return(@node)
    
    client = Chef::Client.new
    client.node = @node
    client.stub!(:sync_cookbooks).and_return({})
    client.run
    
    # check that node has been filled in correctly
    @node.automatic_attrs[:platform].should  eql "example-platform"
    @node.automatic_attrs[:platform_version].should eql "example-platform-1.0"
  end
  
  describe "solo mode" do
    before(:each) do
      Chef::Config[:solo]=true
      @state_path = "#{Chef::Config[:node_path]}/#{@node.name}.json"
      @client = Chef::Client.new
      Chef::Node.should_receive(:find_or_create).and_return(@node)
      @client.node = @node
    end
    
    it "load state file" do
      @client.node.should_receive(:save).and_return(true)
      @client.run
    end
    
    it "save state file" do
      run_context = Chef::RunContext.new(@node, {})
      resource = Chef::Resource::File.new(@state_path)
      provider = Chef::Provider::File.new(resource, run_context)
      Chef::Provider::File.should_receive(:new).and_return(provider)
      provider.should_receive(:action_create)
      provider.should_receive(:set_content)
      @client.run
    end
    
  end
  
end

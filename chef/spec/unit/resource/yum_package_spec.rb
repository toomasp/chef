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
#

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "spec_helper"))

describe Chef::Resource::YumPackage, "initialize" do
  
  before(:each) do
    @resource = Chef::Resource::YumPackage.new("foo")
  end
  
  it "should return a Chef::Resource::YumPackage" do
    @resource.should be_a_kind_of(Chef::Resource::YumPackage)
  end
  
  it "should set the resource_name to :yum_package" do
    @resource.resource_name.should eql(:yum_package)
  end
  
  it "should set the provider to Chef::Provider::Package::Yum" do
    @resource.provider.should eql(Chef::Provider::Package::Yum)
  end
end

describe Chef::Resource::YumPackage, "arch" do
  before(:each) do
    @resource = Chef::Resource::YumPackage.new("foo")
  end

  it "should set the arch variable to whatever is passed in" do
    @resource.arch("i386")
    @resource.arch.should eql("i386")
  end
end

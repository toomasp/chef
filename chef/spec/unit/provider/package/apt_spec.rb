#
# Author:: Adam Jacob (<adam@opscode.com>)
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

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Package::Apt do
  before(:each) do
    @node = Chef::Node.new
    @node.cookbook_collection = {}
    @run_context = Chef::RunContext.new(@node, {})
    @new_resource = Chef::Resource::Package.new("irssi", @run_context)
    @current_resource = Chef::Resource::Package.new("irssi", @run_context)

    @status = mock("Status", :exitstatus => 0)
    @provider = Chef::Provider::Package::Apt.new(@new_resource, @run_context)
    Chef::Resource::Package.stub!(:new).and_return(@current_resource)
    @provider.stub!(:popen4).and_return(@status)
    @stdin = mock("STDIN", :null_object => true)
    @stdout =<<-PKG_STATUS
Package: irssi
State: not installed
Version: 0.8.12-7
PKG_STATUS
    @stderr = mock("STDERR", :null_object => true)
    @pid = mock("PID", :null_object => true)
    @shell_out = OpenStruct.new(:stdout => @stdout,:stdin => @stdin,:stderr => @stderr,:status => @status,:exitstatus => 0)
  end

  describe "when loading current resource" do

    it "should create a current resource with the name of the new_resource" do
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      Chef::Resource::Package.should_receive(:new).and_return(@current_resource)
      @provider.load_current_resource
    end

    it "should set the current resources package name to the new resources package name" do
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      @current_resource.should_receive(:package_name).with(@new_resource.package_name)
      @provider.load_current_resource
    end

    it "should run aptitude show with the package name" do
      @provider.should_receive(:shell_out!).with("aptitude show #{@new_resource.package_name}").and_return(@shell_out)
      @provider.load_current_resource
    end

    it "should set the installed version to nil on the current resource if package state is not installed" do
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      @current_resource.should_receive(:version).with(nil).and_return(true)
      @provider.load_current_resource
    end

    it "should set the installed version if package has one" do
      @stdout.replace(<<-INSTALLED)
Package: irssi
State: installed
Version: 0.8.12-7
INSTALLED
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      @provider.load_current_resource
      @current_resource.version.should == "0.8.12-7"
      @provider.candidate_version.should eql("0.8.12-7")
    end

    it "should raise an exception if aptitude show does not return a candidate version" do
      @stdout.replace("E: Unable to locate package magic")
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      lambda { @provider.load_current_resource }.should raise_error(Chef::Exceptions::Package)
    end

    it "should return the current resouce" do
      @provider.should_receive(:shell_out!).and_return(@shell_out)
      @provider.load_current_resource.should eql(@current_resource)
    end

    it "should set candidate version to new package name if virtual package" do
      @new_resource.package_name("libmysqlclient-dev")
      virtual_package_out=<<-VPKG_STDOUT
"No current or candidate version found for libmysqlclient-dev").
Package: libmysqlclient-dev
State: not a real package
Provided by: libmysqlclient15-dev
VPKG_STDOUT
      virtual_package = mock(:stdout => virtual_package_out,:exitstatus => 0)
      @provider.should_receive(:shell_out!).with("aptitude show libmysqlclient-dev").and_return(virtual_package)
      real_package_out=mock("STDOUT", :null_object => true)
      real_package_out =<<-REALPKG_STDOUT
Package: libmysqlclient15-dev
State: not installed
Version: 5.0.51a-24+lenny4
REALPKG_STDOUT
      real_package = mock(:stdout => real_package_out,:exitstatus => 0)
      @provider.should_receive(:shell_out!).with("aptitude show libmysqlclient15-dev").and_return(real_package)
      @provider.load_current_resource
      @provider.candidate_version.should eql("libmysqlclient15-dev")
    end

    it "should set candidate version to the depends package name if multiple virtual package providers" do
      @new_resource.package_name("mysql-client")
      virtual_package_out=<<-VPKG_STDOUT
Package: mysql-client
State: not installed
Version: 5.1.41-3ubuntu12.6
Depends: mysql-client-5.1
Provided by: mysql-cluster-client-5.1, mysql-client-5.1
Description: MySQL database client (metapackage depending on the latest version)
VPKG_STDOUT
      virtual_package = mock(:stdout => virtual_package_out,:exitstatus => 0)
      @provider.should_receive(:shell_out!).with("aptitude show mysql-client").and_return(virtual_package)
      real_package_out=<<-REALPKG_STDOUT
Package: mysql-client-5.1
State: not installed
Version: Version: 5.1.41-3ubuntu12.6
Conflicts: mysql-client (< 5.1.41-3ubuntu12.6), mysql-client-5.0
Replaces: mysql-client (< 5.1.41-3ubuntu12.6), mysql-client-5.0
Provides: mysql-client, mysql-client-4.1, virtual-mysql-client
REALPKG_STDOUT
      real_package = mock(:stdout => real_package_out,:exitstatus => 0)
      @provider.should_receive(:shell_out!).with("aptitude show mysql-client-5.1").and_return(real_package)
      @provider.load_current_resource
      @provider.candidate_version.should eql("mysql-client-5.1")
    end

  end

  describe "install_package" do

    it "should run apt-get install with the package name and version" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y install irssi=0.8.12-7",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @provider.install_package("irssi", "0.8.12-7")
    end

    it "should run apt-get install with the package name and version and options if specified" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y --force-yes install irssi=0.8.12-7",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @new_resource.stub!(:options).and_return("--force-yes")

      @provider.install_package("irssi", "0.8.12-7")
    end
  end

  describe Chef::Provider::Package::Apt, "upgrade_package" do

    it "should run install_package with the name and version" do
      @provider.should_receive(:install_package).with("irssi", "0.8.12-7")
      @provider.upgrade_package("irssi", "0.8.12-7")
    end
  end

  describe Chef::Provider::Package::Apt, "remove_package" do

    it "should run apt-get remove with the package name" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y remove irssi",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @provider.remove_package("irssi", "0.8.12-7")
    end

    it "should run apt-get remove with the package name and options if specified" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y --force-yes remove irssi",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @new_resource.stub!(:options).and_return("--force-yes")

      @provider.remove_package("irssi", "0.8.12-7")
    end
  end

  describe "when purging a package" do

    it "should run apt-get purge with the package name" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y purge irssi",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @provider.purge_package("irssi", "0.8.12-7")
    end

    it "should run apt-get purge with the package name and options if specified" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "apt-get -q -y --force-yes purge irssi",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      })
      @new_resource.stub!(:options).and_return("--force-yes")

      @provider.purge_package("irssi", "0.8.12-7")
    end
  end

  describe "when preseeding a package" do
    before(:each) do
      @provider.stub!(:get_preseed_file).and_return("/tmp/irssi-0.8.12-7.seed")
      @provider.stub!(:run_command_with_systems_locale).and_return(true)
    end

    it "should get the full path to the preseed response file" do
      @provider.should_receive(:get_preseed_file).with("irssi", "0.8.12-7").and_return("/tmp/irssi-0.8.12-7.seed")
      @provider.preseed_package("irssi", "0.8.12-7")
    end

    it "should run debconf-set-selections on the preseed file if it has changed" do
      @provider.should_receive(:run_command_with_systems_locale).with({
        :command => "debconf-set-selections /tmp/irssi-0.8.12-7.seed",
        :environment => {
          "DEBIAN_FRONTEND" => "noninteractive"
        }
      }).and_return(true)
      @provider.preseed_package("irssi", "0.8.12-7")
    end

    it "should not run debconf-set-selections if the preseed file has not changed" do
      @provider.stub!(:get_preseed_file).and_return(false)
      @provider.should_not_receive(:run_command_with_systems_locale)
      @provider.preseed_package("irssi", "0.8.12-7")
    end
  end
end

#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2009 Opscode, Inc.
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

require 'chef/knife'
require 'chef/data_bag_item'

class Chef
  class Knife
    class Ssh < Knife

      attr_writer :password

      banner "Sub-Command: ssh QUERY COMMAND (options)"

      option :concurrency,
        :short => "-C NUM",
        :long => "--concurrency NUM",
        :description => "The number of concurrent connections",
        :default => nil 

      option :attribute,
        :short => "-a ATTR",
        :long => "--attribute ATTR",
        :description => "The attribute to use for opening the connection - default is fqdn",
        :default => "fqdn" 

      option :manual,
        :short => "-m",
        :long => "--manual-list",
        :boolean => true,
        :description => "QUERY is a space separated list of servers",
        :default => false

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username"

      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      def session
        @session ||= Net::SSH::Multi.start(:concurrent_connections => config[:concurrency])
      end

      def h
        @highline ||= HighLine.new
      end

      def configure_session
        list = case config[:manual]
               when true
                 @name_args[0].split(" ")
               when false
                 r = Array.new
                 q = Chef::Search::Query.new
                 q.search(:node, @name_args[0]) do |item|
                   r << format_for_display(item)[config[:attribute]]
                 end
                 r
               end
        (Chef::Log.fatal("No nodes returned from search!"); exit 10) if list.length == 0
        session_from_list(list)
      end

      def session_from_list(list)
        list.each do |item|
          Chef::Log.debug("Adding #{item}")
         
          if config[:password]
            session.use config[:ssh_user] ? "#{config[:ssh_user]}@#{item}" : item, :password => config[:password]
          else
            session.use config[:ssh_user] ? "#{config[:ssh_user]}@#{item}" : item
          end
          @longest = item.length if item.length > @longest
        end
        session
      end

      def fixup_sudo(command)
        command.sub(/^sudo/, 'sudo -p \'knife sudo password: \'')
      end

      def print_data(host, data)
        if data =~ /\n/
          data.split(/\n/).each { |d| print_data(host, d) }
        else
          padding = @longest - host.length
          print h.color(host, :cyan)
          padding.downto(0) { print " " }
          puts data
        end
      end

      def ssh_command(command, subsession=nil)
        subsession ||= session
        command = fixup_sudo(command)
        subsession.open_channel do |ch|
          ch.request_pty
          ch.exec command do |ch, success|
            raise ArgumentError, "Cannot execute #{command}" unless success
            ch.on_data do |ichannel, data|
              print_data(ichannel[:host], data)
              if data =~ /^knife sudo password: /
                ichannel.send_data("#{get_password}\n")
              end
            end
          end
        end
        session.loop
      end

      def get_password
        @password ||= h.ask("Enter your password: ") { |q| q.echo = false }
      end

      # Present the prompt and read a single line from the console. It also
      # detects ^D and returns "exit" in that case. Adds the input to the
      # history, unless the input is empty. Loops repeatedly until a non-empty
      # line is input.
      def read_line
        loop do
          command = reader.readline("#{h.color('knife-ssh>', :bold)} ", true)

          if command.nil?
            command = "exit"
            puts(command)
          else
            command.strip!
          end

          unless command.empty?
            return command
          end
        end
      end

      def reader
        Readline
      end

      def interactive
        puts "Connected to #{h.list(session.servers_for.collect { |s| h.color(s.host, :cyan) }, :inline, " and ")}"
        puts
        puts "To run a command on a list of servers, do:"
        puts "  on SERVER1 SERVER2 SERVER3; COMMAND"
        puts "  Example: on latte foamy; echo foobar"
        puts
        puts "To exit interactive mode, use 'quit!'"
        puts
        while 1
          command = read_line
          case command
          when 'quit!'
            puts 'Bye!'
            break
          when /^on (.+?); (.+)$/
            raw_list = $1.split(" ")
            server_list = Array.new
            session.servers.each do |session_server|
              server_list << session_server if raw_list.include?(session_server.host) 
            end
            command = $2
            ssh_command(command, session.on(*server_list))
          else
            ssh_command(command)
          end
        end
      end

      def screen
        tf = Tempfile.new("knife-ssh-screen")
        if File.exist? "#{ENV["HOME"]}/.screenrc"
          tf.puts("source #{ENV["HOME"]}/.screenrc")
        end
        tf.puts("caption always '%-Lw%{= BW}%50>%n%f* %t%{-}%+Lw%<'")
        tf.puts("hardstatus alwayslastline 'knife ssh #{@name_args[0]}'")
        window = 0
        session.servers_for.each do |server|
          tf.print("screen -t \"#{server.host}\" #{window} ssh ")
          server.user ? tf.puts("#{server.user}@#{server.host}") : tf.puts(server.host)
          window += 1
        end
        tf.close
        exec("screen -c #{tf.path}")
      end

      def tmux
        begin
          Chef::Mixin::Command.run_command(:command => "tmux new-session -d -s 'knife'")
        rescue Chef::Exceptions::Exec
        end
        session.servers_for.each do |server|
          begin
            Chef::Mixin::Command.run_command(:command => "tmux new-window -d -n '#{server.host}' -t 'knife' 'ssh #{server.user ? "#{server.user}@#{server.host}" : server.host}'")
          rescue Chef::Exceptions::Exec
          end
        end
        exec("tmux attach-session -t knife")
      end

      def macterm
        require 'appscript'
        Appscript.app("/Applications/Utilities/Terminal.app").windows.first.activate  
        Appscript.app("System Events").application_processes["Terminal.app"].keystroke("n", :using=>:command_down)
        term = Appscript.app('Terminal')  
        window = term.windows.first.get
        session.servers_for.each do |server|
          Appscript.app("System Events").application_processes["Terminal.app"].keystroke("t", :using=>:command_down)
          cmd = "unset PROMPT_COMMAND; echo -e \"\\033]0;#{server.host}\\007\"; ssh #{server.user ? "#{server.user}@#{server.host}" : server.host}"
          Appscript.app('Terminal').do_script(cmd, :in => window.tabs.last.get)
          sleep 1
        end
      end

      def run 
        @longest = 0

        require 'net/ssh/multi'
        require 'readline'
        require 'highline'

        configure_session

        case @name_args[1]
        when "interactive"
          interactive 
        when "screen"
          screen
        when "tmux"
          tmux
        when "macterm"
          macterm
        else
          ssh_command(@name_args[1..-1].join(" "))
        end

        session.close
      end
    end
  end
end


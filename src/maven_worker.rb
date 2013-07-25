# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'maestro_shell'
require 'open-uri'
require 'xmlsimple'

module MaestroDev
  module MavenPlugin
    class ConfigError < StandardError
    end
    
    class PluginError < StandardError
    end
  
    class MavenWorker < Maestro::MaestroWorker
  
      def execute
        write_output("\nMAVEN task starting", :buffer => true)
  
        begin
          validate_execute_parameters
  
          Maestro.log.info "Inputs: goals = #{@goals}"
          Maestro.log.debug "Using Maven version #{@mvn_version}" if !@mvn_version.empty?
  
          shell = Maestro::Util::Shell.new
          command = create_command
          shell.create_script(command)
  
          write_output("\nRunning command:\n----------\n#{command.chomp}\n----------\n")
          exit_code = shell.run_script_with_delegate(self, :on_output)
  
          @error = shell.output unless exit_code.success?
        rescue ConfigError => e
          @error = e.message
        rescue Exception => e
          @error = "Error executing Maven Task: #{e.class} #{e}"
          Maestro.log.warn("Error executing Maven Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
        end
  
        write_output "\n\nMAVEN task complete\n"
        set_error(@error) if @error
      end
        
      def wget_latest_snapshot
        write_output("\nWGET_LATEST_SNAPSHOT task starting", :buffer => true)
    
        begin
          validate_snapshot_parameters
    
          Maestro.log.info "Inputs: path =      #{@path}," \
                           "        url =       #{@base_url}," \
                           "        packaging = #{@packaging}"
  
          maven_metadata_xml = get_maven_metadata_xml
  
          artifactId = maven_metadata_xml["artifactId"][0]
  
          unless maven_metadata_xml["versioning"].nil? or maven_metadata_xml["versioning"][0]["snapshot"][0]["timestamp"].nil?
            buildNumber = maven_metadata_xml["versioning"][0]["snapshot"][0]["buildNumber"][0]
            timestamp = maven_metadata_xml["versioning"][0]["snapshot"][0]["timestamp"][0]
            version = maven_metadata_xml["version"][0].gsub(/\-SNAPSHOT/,'')        
            file = "#{artifactId}-#{version}-#{timestamp}-#{buildNumber}.#{@packaging}"
          else
            version = maven_metadata_xml["version"][0]
            file = "#{artifactId}-#{version}.#{@packaging}"
          end
  
          url = @base_url + "/#{file}"
  
          Maestro.log.debug "Removing Existing File At #{@path}/#{artifactId}.#{@packaging}"
  
          begin
            FileUtils.rm "#{@path}/#{artifactId}.#{@packaging}"
          rescue Exception
          end
  
          write_output("\nDownloading File From #{url}", :buffer => true)
  
          wget = Maestro::Util::Shell.new
          command = "#{@wget_executable} --progress=dot #{url} -O #{@path}/#{artifactId}.#{@packaging} --user=#{@username} --password=#{@password}"
          wget.create_script(command)
          write_output("\nRunning command:\n----------\n#{command.chomp}\n----------\n")
          exit_code = wget.run_script_with_delegate(self, :on_output)
  
          write_output("\nDownloaded File #{url} To #{@path}/#{artifactId}.#{@packaging}", :buffer => true) if File.exists? "#{@path}/#{artifactId}.#{@packaging}"
          raise PluginError, "Failed to download #{url} to #{@path}/#{artifactId}.#{@packaging}" unless exit_code.success?
        rescue ConfigError, PluginError => e
          @error = e.message
        rescue Exception => e
          @error = "Error executing Maven wget_latest_snapshot Task: #{e.class} #{e}"
          Maestro.log.warn("Error executing Maven wget_latest_snapshot Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
        end
  
        write_output "\n\nWGET_LATEST_SNAPSHOT task complete\n"
        set_error(@error) if @error
      end
  
      def on_output(text)
        write_output(text, :buffer => true)
      end
  
      ###########
      # PRIVATE #
      ###########
      private
  
      # because we want to be able to string stuff together with &&
      # can't really test the executable.
      def valid_executable?(executable)
        Maestro::Util::Shell.run_command("#{executable} --version")[0].success?
      end
  
      def get_version
        result = Maestro::Util::Shell.run_command("#{@mvn_executable} -version")
        result[1].split("\n")[0].split(' (')[0].split(' ')[2] if result[0].success?
      end
  
      def validate_execute_parameters
        errors = []
  
        @mvn_executable = get_field('maven_executable', 'mvn')
        @mvn_version = get_field('maven_version', '')
        @path = get_field('path') || get_field('scm_path')
        @goals = get_field('goals', '')
        @settingsfile = get_field('settingsfile', '')
        @profiles = get_field('profiles', '')
        @properties = get_field('properties', '')
        @environment = get_field('environment', '')
        @env = @environment.empty? ? "" : "#{Maestro::Util::Shell::ENV_EXPORT_COMMAND} #{@environment.gsub(/(&&|[;&])\s*$/, '')} && "
  
        if valid_executable?(@mvn_executable)
          if !@mvn_version.empty?
            version = get_version
            errors << "maven is the wrong version: #{version}. Expected: #{@mvn_version}" if version != @mvn_version
          end
        else
          errors << 'maven not installed'       
        end
  
        errors << 'missing field path' if @path.nil?
        errors << "not found path '#{@path}'" if !@path.nil? && !File.exist?(@path)
  
        if !@settingsfile.empty?
          if !File.exists?(@settingsfile)
            errors << "specified settings file (#{@settingsfile}) not found"
          end
        end
  
        process_goals_field
        process_profiles_field
        process_properties_field
  
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
  
      def validate_snapshot_parameters
        errors = []
      
        @base_url = get_field('url', '')
        @path = get_field('path', '')
        @username = get_field('username', '')
        @password = get_field('password', '')
        @packaging = get_field('packaging', '')
        @wget_executable = get_field('wget_executable', 'wget')
   
        errors << 'missing field url' if @base_url.empty?   
        errors << 'missing field path' if @path.empty?
        errors << "path not found '#{@path}'" if !@path.empty? && !File.exist?(@path)
        errors << 'missing field username' if @username.empty?
        errors << 'missing field password' if @password.empty?
        errors << 'missing field packaging' if @packaging.empty?
        errors << 'wget not installed' unless valid_executable?(@wget_executable)
  
        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end
  
      def process_goals_field
        begin
          if is_json(@goals)
            @goals = JSON.parse(@goals) if @goals.is_a? String
          end
        rescue Exception  
        end
        
        if @goals.is_a? Array
          @goals = @goals.join(' ')
        end
      end
  
      def process_profiles_field
        begin
          if is_json(@profiles)
            @profiles = JSON.parse(@profiles) if @profiles.is_a? String
          end
        rescue Exception  
        end
  
        if @profiles.is_a? Array
          @profiles.delete_if{ |profile| profile.empty? }
          @profiles = @profiles.join(',')
        end
        
        Maestro.log.debug "Enabling Maven profiles: #{@profiles}"
        @profiles = " -P#{@profiles}" unless @profiles.empty?
      end
  
      def process_properties_field
        begin
          if is_json(@properties)
            @properties = JSON.parse(@properties) if @properties.is_a? String
          end
        rescue Exception  
        end
  
        if @properties.is_a? Array
          @properties.delete_if{ |property| property.empty? }
          @properties = @properties.map{|x| "-D#{x}"}.join(' ')
        end
  
        Maestro.log.debug "Using Maven properties: #{@properties}"
      end
  
      def create_command
        settings = "--settings #{@settingsfile} " if !@settingsfile.empty?
        shell_command = "#{@env}cd #{@path} && #{@mvn_executable} -B #{settings}#{@goals}#{@profiles} #{@properties}"
        set_field('command', shell_command)
        Maestro.log.debug("Running #{shell_command}")
        shell_command
      end
  
      def get_maven_metadata_xml
        write_output "\nRequesting maven-metadata.xml With Username #{@username} And Password"
  
        begin
          response = open(@base_url + "/maven-metadata.xml", :http_basic_authentication => [@username, @password])
  
          raise PluginError, 'Failed To Retrieve maven-metadata.xml (no response from server)' unless response
  
          case response.status[0]
          when "200"
            maven_metadata_xml = XmlSimple.xml_in(response.read)
            Maestro.log.debug "\nResponse Received #{response.status[0]}\n#{maven_metadata_xml}"
          else
            raise PluginError, "Failed To Retrieve maven-metadata.xml #{response}"
          end
    
          raise PluginError, "Missing Version Or ArtifactID " if maven_metadata_xml["artifactId"].nil? or maven_metadata_xml["version"].nil?
        rescue
          raise PluginError, 'Failed To Retrieve maven-metadata.xml (unable to connect to server)'
        end
  
        maven_metadata_xml
      end
  
    end
  end
end

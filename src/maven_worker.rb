# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'maestro_shell'

module MaestroDev
  class ConfigError < StandardError
  end

  class MavenWorker < Maestro::MaestroWorker

    def execute
      write_output("\nMAVEN task starting", :buffer => true)

      begin
        validate_parameters

        Maestro.log.info "Inputs: goals = #{@goals}"
        Maestro.log.debug "Using Maven version #{@mvn_version}" if !@mvn_version.empty?

        shell = Maestro::Util::Shell.new
        shell.create_script(create_command)

        exit_code = shell.run_script_with_delegate(self, :on_output)

        @error = shell.output unless exit_code.success?
      rescue ConfigError => e
        @error = e.message
      rescue Exception => e
        @error = "Error executing Maven Task: #{e.class} #{e}"
        Maestro.log.warn("Error executing Maven Task: #{e.class} #{e}: " + e.backtrace.join("\n"))
      end

      write_output "\n\nMAVEN task complete"
      set_error(@error) if @error
    end

    def on_output(text, is_stderr)
      write_output(text, :buffer => true)
    end

    ###########
    # PRIVATE #
    ###########
    private

    # because we want to be able to string stuff together with &&
    # can't really test the executable.
    def valid_executable?
      Maestro::Util::Shell.run_command("#{@mvn_executable} --version")[0].success?
    end

    def get_version
      result = Maestro::Util::Shell.run_command("#{@mvn_executable} -version")
      result[1].split("\n")[0].split(' (')[0].split(' ')[2] if result[0].success?
    end

    def validate_parameters
      errors = []

      @mvn_executable = get_field('maven_executable', 'mvn')
      @mvn_version = get_field('maven_version', '')
      @path = get_field('path') || get_field('scm_path')
      @goals = get_field('goals', '')
      @settingsfile = get_field('settingsfile', '')
      @profiles = get_field('profiles', '')
      @properties = get_field('properties', '')
      @environment = get_field('environment', '')

      if valid_executable?
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
      shell_command = "#{@environment} cd #{@path} && #{@mvn_executable} -B #{settings}#{@goals}#{@profiles} #{@properties}"
      set_field('command', shell_command)
      Maestro.log.debug("Running #{shell_command}")
      shell_command
    end

  end
end

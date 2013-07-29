# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
# 
#  http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'spec_helper'

describe MaestroDev::Plugin::MavenWorker do
  MAVEN = 'Apache Maven'
  MAVEN_VERSION = 'Apache Maven 3.0.3'
  before(:all) do
    Maestro::MaestroWorker.mock!
  end

  describe 'valid_workitem?' do
    it "should validate fields" do
      workitem = {'fields' =>{}}

      subject.perform(:execute, workitem)

      workitem['fields']['__error__'].should include('missing field path')
    end

    it "should detect maven not present" do
      workitem = {'fields' => {'goals' => '', 'path' => '/tmp', 'maven_executable' => '/dev/nul'}}

      subject.perform(:execute, workitem)

      workitem['fields']['__error__'].should include('maven not installed')
    end

    it "should error if wrong version detected" do
      workitem = {'fields' => {'goals' => '',
                               'path' => '/tmp',
                               'maven_version' => '99.99.99'}}

      subject.perform(:execute, workitem)

      workitem['fields']['__error__'].should include('maven is the wrong version')
    end

    it "should error if propertyfile not found" do
      settingsfile = '/tmp/blah.settings.xml'
      workitem = {'fields' => {'goals' => '',
                               'path' => '/tmp',
                               'settingsfile' => settingsfile}}

      subject.perform(:execute, workitem)

      workitem['fields']['__error__'].should include("specified settings file (#{settingsfile}) not found")
    end

    it "should not error if everything is ok" do
      `touch /tmp/test.settings.xml`

      workitem = {'fields' => {'goals' => '',
                               'path' => '/tmp',
                               'propertyfile' => '/tmp/test.settings.xml'}}

      subject.perform(:execute, workitem)
      # It got as far as executing maven... we're all good
      workitem['fields']['__error__'].should start_with("Maven failed executing goal list '[default]'\n[ERROR]")
    end
  end

  describe 'execute' do
    before :each do
      @path = File.join(File.dirname(__FILE__), '..', '..')
      @workitem =  {'fields' => {'goals' => '',
                                 'path' => @path}}
    end

    it 'should run maven' do
      @workitem['fields']['goals'] = '-version'

      subject.perform(:execute, @workitem)

      @workitem['fields']['__error__'].should be_nil
      @workitem['__output__'].should include(MAVEN)
      @workitem['__output__'].should_not include("ERROR")
    end

    it 'should run maven with goals in real array' do
      @workitem['fields']['goals'] = ['-version']

      subject.perform(:execute, @workitem)

      @workitem['fields']['__error__'].should be_nil
      @workitem['__output__'].should include(MAVEN)
      @workitem['__output__'].should_not include("ERROR")
    end

    it 'should add settings, environment, properties and profiles to command line if specified' do
      settingsfile = File.join(File.dirname(__FILE__), '..', 'spec-data', 'settings.xml')
      @workitem['fields']['goals'] = '-version'
      @workitem['fields']['environment'] = 'M2_HOME=/tmp'
      @workitem['fields']['profiles'] = ['myprofile', '-anotherprofile', '']
      @workitem['fields']['properties'] = ['x=y', 'a=b', '']
      @workitem['fields']['settingsfile'] = settingsfile

      subject.perform(:execute, @workitem)

      expected = "export M2_HOME=/tmp && cd #{@path} && mvn -B --settings #{settingsfile} -version -Pmyprofile,-anotherprofile -Dx=y -Da=b"
      @workitem['fields']['command'].should eql(expected)
    end

    it 'should not add settings or environment to command line if not specified' do
      @workitem['fields']['goals'] = '-version'

      subject.perform(:execute, @workitem)

      expected = "cd #{@path} && mvn -B -version "
      @workitem['fields']['command'].should eql(expected)
    end

    it 'should not add empty properties or profiles to command line' do
      @workitem['fields']['goals'] = '-version'

      # test with '', [], ['']
      inputs = ['',[],['']]
      inputs.each do |i|
        @workitem['fields']['properties'] = i
        @workitem['fields']['profiles'] = i

        subject.perform(:execute, @workitem)

        expected = "cd #{@path} && mvn -B -version "
        @workitem['fields']['command'].should eql(expected)
      end
    end

  end

  describe "wget_latest_snapshot()" do
    @@user = 'user'
    @@password = 'password'
    @@archive_url = "127.0.0.1:18081/archiva/repository/snapshots/com/effectivemaven/centrepoint/webapp/1.0-SNAPSHOT/"

    @@sample =<<-XML
    <metadata>
    <groupId>com.effectivemaven.centrepoint</groupId>
    <artifactId>webapp</artifactId>
    <version>1.0-SNAPSHOT</version>
    <versioning>
    <snapshot>
    <buildNumber>1</buildNumber>
    <timestamp>20111005.232734</timestamp>
    </snapshot>
    <lastUpdated>20111005232751</lastUpdated>
    </versioning>
    </metadata>
    XML
    
    @@bad_sample =<<-XML
    <metadata>
    <groupId>com.effectivemaven.centrepoint</groupId>
    <artifactId>webapp</artifactId>
    <version>1.0-SNAPSHOT</version>
    <versioning>
    <snapshot>
    </snapshot>
    <lastUpdated>20111005232751</lastUpdated>
    </versioning>
    </metadata>
    XML
    
    @@maven_metadata_xml = {"versioning"=>
                              [{"snapshot"=>[{"buildNumber"=>["2"], "timestamp"=>["20111006.205136"]}],
                                  "lastUpdated"=>["20111006205240"]}],
                            "artifactId"=>["webapp"],
                            "version"=>["1.0-SNAPSHOT"],
                            "groupId"=>["com.effectivemaven.centrepoint"]}
    @@maven_metadata_xml_release =<<XML
<metadata>
<groupId>com.maestrodev.lucee</groupId>
<artifactId>lucee</artifactId>
<version>0.0.15</version>
</metadata>
XML

    it "should download the latest snapshot" do
      workitem = {'fields' => { 'wget_executable' => 'echo Yo File Is Downloaded', 'username' => @@user,  'password' => @@password, 'path' => '/tmp/', 'packaging' => 'war', 'url' => "http://#{@@archive_url}"}}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@archive_url}/maven-metadata.xml").to_return(:body => @@sample)

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should be_nil
    end

    it "should download the release" do
      workitem = {'fields' => { 'wget_executable' => 'echo Yo File Is Downloaded', 'username' => @@user,  'password' => @@password, 'path' => '/tmp/', 'packaging' => 'war', 'url' => "http://#{@@archive_url}"}}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@archive_url}/maven-metadata.xml").to_return(:body => @@maven_metadata_xml_release)

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should be_nil
    end

    it "should error if url is not specified" do
      workitem = {'fields' => {'username' => 'name',  'password' => '********','path' => '/tmp/', 'packaging'=>'war'}}

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should include("missing field url")
    end

    it "should error if packaging is not specified" do
      workitem = {'fields' => {'username' => 'name',  'password' => '********','path' => '/tmp/', 'url'=>'hello'}}

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should include("missing field packaging")
    end

    it "should error if path not specified" do
      workitem = {'fields' => {'username' => 'name',  'password' => '********','url' => 'http://blah.com/', 'packaging'=>'war'}}

      subject.perform(:wget_latest_snapshot, workitem)
      
      workitem['fields']['__error__'].should include("missing field path")
    end

    it "should error if path not found" do
      workitem = {'fields' => {'username' => 'name',  'password' => '********','path' => '/tmp/please_dont_be_real', 'packaging'=>'war'}}
      
      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should include("path not found '/tmp/please_dont_be_real'")
    end

    it "should error if unable to connect" do
      workitem = {'fields' => {'wget_executable' => 'echo Yo File Is Downloaded', 'username' => @@user, 'password' => @@password, 'path' => '/tmp/', 'url' => "http://#{@@archive_url}", 'packaging'=>'war'}}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@archive_url}/maven-metadata.xml").to_timeout

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should include("Failed To Retrieve maven-metadata.xml")
    end
    
    it "should error if maven-metadata.xml not found" do
      workitem = {'fields' => {'wget_executable' => 'echo Yo File Is Downloaded', 'username' => @@user, 'password' => @@password, 'path' => '/tmp/', 'url' => "http://#{@@archive_url}", 'packaging'=>'war'}}
      
      subject.perform(:wget_latest_snapshot, workitem)
      
      workitem['fields']['__error__'].should include("Failed To Retrieve maven-metadata.xml")
    end
    
    it "should error if get maven-metadata.xml works and package doesn't" do
      workitem = {'fields' => {'wget_executable' => 'echo "if [ \"\$1\" == \"--version\" ]; then exit 0; else echo Fail && exit 1; fi" > /tmp/xyz; sh /tmp/xyz', 'username' => @@user, 'password' => @@password, 'path' => '/tmp/', 'url' => "http://#{@@archive_url}", 'packaging' => 'via ups'}}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@archive_url}/maven-metadata.xml").to_return(:body => @@maven_metadata_xml_release)

      subject.perform(:wget_latest_snapshot, workitem)

      workitem['fields']['__error__'].should include("Failed to download")
    end
    
  end

end

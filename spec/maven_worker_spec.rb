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

describe MaestroDev::MavenWorker do
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

      workitem['fields']['__error__'].should include('[INFO] Scanning for projects...')
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

end

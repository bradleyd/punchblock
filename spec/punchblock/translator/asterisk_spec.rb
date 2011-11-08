require 'spec_helper'

module Punchblock
  module Translator
    describe Asterisk do
      let(:ami_client) { mock 'RubyAMI::Client' }
      let(:connection) { mock 'Connection::Asterisk' }

      subject { Asterisk.new ami_client, connection }

      its(:ami_client) { should be ami_client }
      its(:connection) { should be connection }

      describe '#execute_command' do
        describe 'with a call command' do
          let(:command) { Command::Answer.new }
          let(:call_id) { 'abc123' }

          it 'executes the call command' do
            subject.actor_subject.expects(:execute_call_command).with do |c|
              c.should be command
              c.call_id.should == call_id
            end
            subject.execute_command command, :call_id => call_id
          end
        end

        describe 'with a component command' do
          let(:command)       { Component::Stop.new }
          let(:call_id)       { 'abc123' }
          let(:component_id)  { '123abc' }

          it 'executes the component command' do
            subject.actor_subject.expects(:execute_component_command).with do |c|
              c.should be command
              c.call_id.should == call_id
              c.component_id.should == component_id
            end
            subject.execute_command command, :call_id => call_id, :component_id => component_id
          end
        end

        describe 'with a global command' do
          let(:command) { Command::Dial.new }

          it 'executes the command directly' do
            subject.actor_subject.expects(:execute_global_command).with command
            subject.execute_command command
          end
        end
      end

      describe '#register_call' do
        it 'should make the call accessible by ID' do
          call_id = 'abc123'
          call    = mock 'Translator::Asterisk::Call', :id => call_id
          subject.register_call call
          subject.call_with_id(call_id).should be call
        end
      end

      describe '#execute_call_command' do
        let(:call_id) { 'abc123' }
        let(:call)    { mock 'Translator::Asterisk::Call', :id => call_id }
        let(:command) { mock 'Command::Answer', :call_id => call_id }

        before do
          subject.register_call call
        end

        it 'sends the command to the call for execution' do
          call.expects(:execute_command).once.with command
          subject.execute_call_command command
        end
      end

      describe '#execute_component_command' do
        let(:call_id) { 'abc123' }
        let(:call)    { Translator::Asterisk::Call.new }

        let(:component_id)  { '123abc' }
        let(:component)     { mock 'Translator::Asterisk::Component', :id => component_id }

        let(:command) { mock 'Component::Stop', :call_id => call_id, :component_id => component_id }

        before do
          call.stubs(:id).returns call_id
          call.register_component component
          subject.register_call call
        end

        it 'sends the command to the component for execution' do
          component.expects(:execute_command).once.with command
          subject.execute_component_command command
        end
      end

      describe '#execute_global_command' do
        context 'with a Dial' do
          pending
        end

        context 'with an AMI action' do
          let :command do
            Component::Asterisk::AMI::Action.new :name => 'Status', :params => { :channel => 'foo' }
          end

          let(:mock_action) { mock 'Asterisk::AMIAction' }

          it 'should create a component actor and execute it asynchronously' do
            Asterisk::AMIAction.expects(:new).once.with(command, subject.ami_client).returns mock_action
            mock_action.expects(:execute!).once
            subject.execute_global_command command
          end
        end
      end

      describe '#handle_ami_event' do
        let :ami_event do
          RubyAMI::Event.new('Newchannel').tap do |e|
            e['Channel']  = "SIP/101-3f3f"
            e['State']    = "Ring"
            e['Callerid'] = "101"
            e['Uniqueid'] = "1094154427.10"
          end
        end

        let :expected_pb_event do
          Event::Asterisk::AMI::Event.new :name => 'Newchannel',
                                          :attributes => { :channel  => "SIP/101-3f3f",
                                                           :state    => "Ring",
                                                           :callerid => "101",
                                                           :uniqueid => "1094154427.10"}
        end

        it 'should create a Punchblock AMI event object and pass it to the connection' do
          subject.connection.expects(:handle_event).once.with expected_pb_event
          subject.handle_ami_event ami_event
        end

        context 'with something that is not a RubyAMI::Event' do
          it 'does not send anything to the connection' do
            subject.connection.expects(:handle_event).never
            subject.handle_ami_event :foo
          end
        end


        describe 'with a FullyBooted event' do
          let(:ami_event) { RubyAMI::Event.new 'FullyBooted' }

          context 'once' do
            it 'does not send anything to the connection' do
              subject.connection.expects(:handle_event).never
              subject.handle_ami_event ami_event
            end
          end

          context 'twice' do
            it 'sends a connected event to the event handler' do
              subject.connection.expects(:handle_event).once.with Connection::Connected.new
              subject.handle_ami_event ami_event
              subject.handle_ami_event ami_event
            end
          end
        end
      end
    end
  end
end
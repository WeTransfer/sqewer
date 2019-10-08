require_relative '../spec_helper'
require_relative '../../lib/sqewer/extensions/appsignal_wrapper.rb'

require 'appsignal'

describe Sqewer::Contrib::AppsignalWrapper do
  class ErroringJob < Struct.new :one
    def run
      raise "This is a complete disaster"
    end
  end

  describe '#around_deserialization' do
    it 'is used for job deserialization (when job gets discarded)' do
      allow(Appsignal).to receive(:active?).and_return(true)
      Appsignal.config = Appsignal::Config.new(Dir.pwd, "sqewer-test")

      wrapper = described_class.new

      job = ErroringJob.new(123)
      serializer = Sqewer::Serializer.new
      payload = serializer.serialize(job)

      wrapper = described_class.new
      expect_any_instance_of(Appsignal::Transaction).to receive(:set_queue_start).with(887268821).and_call_original
      expect_any_instance_of(Appsignal::Transaction).to receive(:set_action).with("Sqewer::Serializer#unserialize").and_call_original
      expect(Appsignal::Transaction).to receive(:complete_current!).and_call_original

      vivified_job = wrapper.around_deserialization(serializer, 'abcdef', payload, _message_attributes = {'SentTimestamp' => '887268821'}) do
        nil # As if the serializer has discarded the job
      end

      expect(vivified_job).to be_nil
    end

    it 'leaves the transaction open with the job transaction name if the job was unserialized and will be run' do
      allow(Appsignal).to receive(:active?).and_return(true)
      Appsignal.config = Appsignal::Config.new(Dir.pwd, "sqewer-test")

      wrapper = described_class.new

      job = ErroringJob.new(123)
      serializer = Sqewer::Serializer.new
      payload = serializer.serialize(job)

      wrapper = described_class.new
      expect_any_instance_of(Appsignal::Transaction).to receive(:set_queue_start).with(887268821).and_call_original
      expect(Appsignal::Transaction).not_to receive(:complete_current!)

      vivified_job = wrapper.around_deserialization(serializer, 'abcdef', payload, _message_attributes = {'SentTimestamp' => '887268821'}) do
        serializer.unserialize(payload)
      end

      expect(vivified_job).to be_kind_of(ErroringJob)
      expect(Appsignal::Transaction.current.action).to eq("ErroringJob#run")
    end

    it 'rescues an error during unserialization and places it in the transaction' do
      allow(Appsignal).to receive(:active?).and_return(true)
      Appsignal.config = Appsignal::Config.new(Dir.pwd, "sqewer-test")

      wrapper = described_class.new

      job = ErroringJob.new(123)
      serializer = Sqewer::Serializer.new
      payload = serializer.serialize(job)

      wrapper = described_class.new
      expect_any_instance_of(Appsignal::Transaction).to receive(:set_queue_start).with(887268821).and_call_original
      expect_any_instance_of(Appsignal::Transaction).to receive(:set_error).and_call_original
      expect(Appsignal::Transaction).to receive(:complete_current!) # And do not call_original since we will assert on it

      expect {
        wrapper.around_deserialization(serializer, 'abcdef', payload, _message_attributes = {'SentTimestamp' => '887268821'}) do
          raise "Could not vivify"
        end
      }.to raise_error(/Could not vivify/)

      expect(Appsignal::Transaction.current.action).to eq("Sqewer::Serializer#unserialize")
    end
  end

  describe '#around_execution' do
    it 'captures the exception during execution and raises it up' do
      allow(Appsignal).to receive(:active?).and_return(true)
      Appsignal.config = Appsignal::Config.new(Dir.pwd, "sqewer-test")

      wrapper = described_class.new

      # Create the appsignal transaction during unserialize, it will be kept open
      serializer = Sqewer::Serializer.new
      payload = serializer.serialize(ErroringJob.new(123))
      job = wrapper.around_deserialization(serializer, 'abcdef', payload, _message_attributes = {'SentTimestamp' => '887268821'}) do
        serializer.unserialize(payload)
      end

      expect_any_instance_of(Appsignal::Transaction).to receive(:set_error).and_call_original
      expect(Appsignal::Transaction).to receive(:complete_current!).and_call_original

      expect {
        wrapper.around_execution(job, _context = {}) { job.run }
      }.to raise_error(/disaster/)
    end

    it 'completes the transaction when the job performs successfully' do
      allow(Appsignal).to receive(:active?).and_return(true)
      Appsignal.config = Appsignal::Config.new(Dir.pwd, "sqewer-test")

      wrapper = described_class.new

      # Create the appsignal transaction during unserialize, it will be kept open
      serializer = Sqewer::Serializer.new
      payload = serializer.serialize(ErroringJob.new(123))
      job = wrapper.around_deserialization(serializer, 'abcdef', payload, _message_attributes = {'SentTimestamp' => '887268821'}) do
        serializer.unserialize(payload)
      end

      expect_any_instance_of(Appsignal::Transaction).not_to receive(:set_error)
      expect(Appsignal::Transaction).to receive(:complete_current!).and_call_original

      wrapper.around_execution(job, _context = {}) { true } # Do not call job.run but just pretend we did something
    end
  end
end

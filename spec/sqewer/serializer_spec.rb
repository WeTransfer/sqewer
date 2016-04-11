require_relative '../spec_helper'

describe Sqewer::Serializer do
  describe '.default' do
    it 'returns the same Serializer instance' do
      instances = (1..1000).map{ described_class.default }
      instances.uniq!
      expect(instances).to be_one
      
      the_instance = instances[0]
      expect(the_instance).to respond_to(:serialize)
      expect(the_instance).to respond_to(:unserialize)
    end
  end
  
  describe '#serialize' do
    
    it 'serializes a Job that has no to_h support without its kwargs' do
      class JobWithoutToHash
      end
      job = JobWithoutToHash.new
      expect(described_class.new.serialize(job)).to eq("{\"_job_class\":\"JobWithoutToHash\",\"_job_params\":null}")
    end
    
    it 'serializes a Struct along with its members and the class name' do
      class SomeJob < Struct.new :one, :two
      end
      
      job = SomeJob.new(123, [456])
      
      expect(described_class.new.serialize(job)).to eq("{\"_job_class\":\"SomeJob\",\"_job_params\":{\"one\":123,\"two\":[456]}}")
    end
    
    it 'adds _execute_after when the value is given' do
      class ThirdJob < Struct.new :one, :two
      end
      
      job = ThirdJob.new(123, [456])
      res = described_class.new.serialize(job, Time.now.to_i + 1500)
      parsed = JSON.load(res)
      
      expect(parsed["_execute_after"]).to be_within(10).of(Time.now.to_i + 1500)
    end
    
    it 'raises an exception if the object is of an anonymous class' do
      s = Struct.new(:foo)
      o = s.new(1)
      expect {
        described_class.new.serialize(o)
      }.to raise_error(described_class::AnonymousJobClass)
    end
  end
  
  it 'is able to roundtrip a job with a parameter' do
    require 'ks'
    
    class LeJob < Ks.strict(:some_data)
    end
  
    job = LeJob.new(some_data: 123)
  
    subject = described_class.new
  
    serialized = subject.serialize(job)
    restored = subject.unserialize(serialized)
  
    expect(restored).to be_kind_of(LeJob)
    expect(restored.some_data).to eq(123)
  end
  
  describe '#unserialize' do
    it 'wraps the job with a Resubmit when the _execute_after key hints that it is too early' do
      class EvenSimplerJob; end
    
      timestamp_way_in_the_future = Time.now.to_i + (60 * 60 * 24 * 3)
      blob  = '{"_job_class": "EvenSimplerJob", "_execute_after": %d}' % timestamp_way_in_the_future
      built_job = described_class.new.unserialize(blob)
    
      expect(built_job).to be_kind_of(Sqewer::Resubmit)
      expect(built_job.execute_after).to eq(timestamp_way_in_the_future)
      
      embedded_job = built_job.job
      expect(embedded_job).to be_kind_of(EvenSimplerJob)
    end
    
    it 'builds a job without keyword arguments if its constructor does not need any kwargs' do
      class EvenSimplerJob; end
    
      blob  = '{"_job_class": "EvenSimplerJob"}'
      built_job = described_class.new.unserialize(blob)
    
      expect(built_job).to be_kind_of(EvenSimplerJob)
    
      blob  = '{"_job_class": "EvenSimplerJob", "_job_params": null}'
      built_job = described_class.new.unserialize(blob)
    
      expect(built_job).to be_kind_of(EvenSimplerJob)
    end
  
    it 'raises an error if the job does not accept the keyword arguments given in the ticket' do
      class MicroJob; end
      blob  = '{"_job_class": "MicroJob", "_job_params":{"foo": 1}}'
      expect {
        described_class.new.unserialize(blob)
      }.to raise_error(ArgumentError)
    end
  
    it 'instantiates the job with keyword arguments' do
      OtherValidJob = Ks.strict(:foo)
    
      blob  = '{"_job_class": "OtherValidJob", "_job_params": {"foo": 1}}'
      built_job = described_class.new.unserialize(blob)
    
      expect(built_job).to be_kind_of(OtherValidJob)
      expect(built_job.foo).to eq(1)
    end
  end
end

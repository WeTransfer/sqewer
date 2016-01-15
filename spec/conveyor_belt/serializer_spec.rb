require_relative '../spec_helper'

describe ConveyorBelt::Serializer do
  describe '#serialize' do
    it 'serializes a Struct along with its members and the class name' do
      class SomeJob < Struct.new :one, :two
      end
      
      job = SomeJob.new(123, [456])
      
      expect(described_class.new.serialize(job)).to eq("{\n  \"job_class\": \"SomeJob\",\n  \"one\": 123,\n  \"two\": [\n    456\n  ]\n}")
    end
    
    it 'raises an exception if the object is of an anonymous class' do
      s = Struct.new(:foo)
      o = s.new(1)
      expect {
        described_class.new.serialize(o)
      }.to raise_error(described_class::AnonymousJobClass)
    end
  end
  
  describe '#unserialize' do
    it 'builds a job without keyword arguments if its constructor does not need any kwargs' do
      class VerySimpleJob; end
      blob  = '{"job_class": "VerySimpleJob"}'
      built_job = described_class.new.unserialize(blob)
      expect(built_job).to be_kind_of(VerySimpleJob)
    end
    
    it 'raises an error if the job does not accept the keeyword arguments given in the ticket' do
      class OtherVerySimpleJob; end
      blob  = '{"job_class": "OtherVerySimpleJob", "foo": 1}'
      
      expect {
        described_class.new.unserialize(blob)
      }.to raise_error(described_class::ArityMismatch)
    end
  end
end

require_relative '../spec_helper'

describe Sqewer::Submitter do
  describe '.default' do
    it 'returns a set up Submitter with the configured Connection and Serializer' do
      expect(ENV).to receive(:fetch).with('SQS_QUEUE_URL').and_return('https://some-queue.aws.com')
      
      s = described_class.default
      expect(s.connection).to respond_to(:send_message)
      expect(s.serializer).to respond_to(:serialize)
    end
  end
  
  describe '#initialize' do
    it 'creates a Submitter that you can submit jobs through' do
      fake_serializer = double('Some serializer')
      allow(fake_serializer).to receive(:serialize) {|object_to_serialize|
        expect(object_to_serialize).not_to be_nil
        'serialized-object-data'
      }
      
      fake_connection = double('Some SQS connection')
      expect(fake_connection).to receive(:send_message).at_least(5).times.with('serialized-object-data', {})
      
      subject = described_class.new(fake_connection, fake_serializer)
      5.times { subject.submit!(:some_object) }
    end
    
    it 'passes the keyword arguments to send_message on the connection' do
      fake_serializer = double('Some serializer')
      allow(fake_serializer).to receive(:serialize) {|object_to_serialize|
        expect(object_to_serialize).not_to be_nil
        'serialized-object-data'
      }
      
      fake_connection = double('Some SQS connection')
      expect(fake_connection).to receive(:send_message).with('serialized-object-data', {delay_seconds: 5})
      
      subject = described_class.new(fake_connection, fake_serializer)
      subject.submit!(:some_object, delay_seconds: 5)
    end
    
    it 'handles the massively delayed execution by clamping the delay_seconds to the SQS maximum, and saving the _execute_after' do
      fake_serializer = double('Some serializer')
      allow(fake_serializer).to receive(:serialize) {|object_to_serialize, timestamp_seconds|
        
        delay_by = Time.now.to_i + 4585659855
        expect(timestamp_seconds).to be_within(20).of(delay_by)
        
        expect(object_to_serialize).not_to be_nil
        'serialized-object-data'
      }
      
      fake_connection = double('Some SQS connection')
      expect(fake_connection).to receive(:send_message).with('serialized-object-data', {delay_seconds: 899})
      
      subject = described_class.new(fake_connection, fake_serializer)
      subject.submit!(:some_object, delay_seconds: 4585659855)
    end
  end
end

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
      expect(fake_connection).to receive(:send_message).at_least(5).times.with('serialized-object-data', any_args)

      fake_job = double('Some job', run: true)

      subject = described_class.new(fake_connection, fake_serializer)
      5.times { subject.submit!(fake_job) }
    end

    it 'passes the keyword arguments to send_message on the connection' do
      fake_serializer = double('Some serializer')
      allow(fake_serializer).to receive(:serialize) {|object_to_serialize|
        expect(object_to_serialize).not_to be_nil
        'serialized-object-data'
      }

      fake_connection = double('Some SQS connection')
      expect(fake_connection).to receive(:send_message).with('serialized-object-data', {delay_seconds: 5})

      fake_job = double('Some job', run: true)

      subject = described_class.new(fake_connection, fake_serializer)
      subject.submit!(fake_job, delay_seconds: 5)
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

      fake_job = double('Some job', run: true)

      subject = described_class.new(fake_connection, fake_serializer)
      subject.submit!(fake_job, delay_seconds: 4585659855)
    end

    it "raises an error if the job does not respond to #run" do
      fake_serializer = double('Some serializer')
      fake_connection = double('Some SQS connection')
      fake_job = double('Some job')

      subject = described_class.new(fake_connection, fake_serializer)
      expect {
        subject.submit!(fake_job, delay_seconds: 5)
      }.to raise_error(Sqewer::Submitter::NotSqewerJob)
    end

    it "raises an error if the job produces a message above the SQS size limit" do
      class VeryLargeTestJob < Struct.new(:some_data)
        def run
        end
      end

      large_blob = Base64.strict_encode64(Random.new.bytes(257*1024))
      large_job = VeryLargeTestJob.new(large_blob)

      fake_serializer = Sqewer::Serializer.default
      fake_connection = double('Some SQS connection')

      subject = described_class.new(fake_connection, fake_serializer)
      expect {
        subject.submit!(large_job)
      }.to raise_error(Sqewer::Submitter::MessageTooLarge, /VeryLargeTestJob/)
    end
  end
end

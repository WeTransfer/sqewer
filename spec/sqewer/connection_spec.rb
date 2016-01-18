require_relative '../spec_helper'

describe Sqewer::Connection do
  describe '.default' do
    it 'returns a new Connection with the SQS queue location picked from SQS_QUEUE_URL envvar' do
      expect(ENV).to receive(:fetch).with('SQS_QUEUE_URL').and_return('https://aws-fake-queue.com')
      default = described_class.default
      expect(default).to be_kind_of(described_class)
    end
  end
  
  describe '#send_message' do
    it 'sends the message to the SQS client created with the URL given to the constructor' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message).
        with({:queue_url=>"https://fake-queue.com", :message_body=>"abcdef"})
      
      conn = described_class.new('https://fake-queue.com')
      conn.send_message('abcdef')
    end
    
    it 'passes keyword args to Aws::SQS::Client' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message).
        with({:queue_url=>"https://fake-queue.com", :message_body=>"abcdef", delay_seconds: 5})
      
      conn = described_class.new('https://fake-queue.com')
      conn.send_message('abcdef', delay_seconds: 5)
    end
  end
  
  describe '#poll' do
    it 'uses the batched receive feature' do
      s = described_class.new('https://fake-queue')
      
      fake_poller = double('QueuePoller')
      expect(::Aws::SQS::QueuePoller).to receive(:new).with('https://fake-queue') { fake_poller }
      expect(fake_poller).to receive(:poll) {|*a, **k, &blk|
        expect(k[:max_number_of_messages]).to be > 1
        bulk = (1..5).map do
          double('SQSMessage', receipt_handle: SecureRandom.hex(4), body: 'Some message')
        end
        # Yields arrays of messages, so...
        blk.call(bulk)
      }
      
      receives = []
      s.poll do | sqs_message_handle, sqs_message_body |
        receives << [sqs_message_handle, sqs_message_body]
      end
      
      expect(receives.length).to eq(5)
    end
  end
end

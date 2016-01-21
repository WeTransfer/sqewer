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
  
  describe '#receive_messages' do
    it 'uses the batched receive feature' do
      s = described_class.new('https://fake-queue')
      
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      
      fake_messages = (1..5).map {
        double(receipt_handle: SecureRandom.hex(4), body: SecureRandom.random_bytes(128))
      }
      fake_response = double(messages: fake_messages)
      
      expect(fake_sqs_client).to receive(:receive_message).with({:queue_url=>"https://fake-queue", :wait_time_seconds=>5, 
          :max_number_of_messages=>10}).and_return(fake_response)
      
      messages = s.receive_messages
      expect(messages.length).to eq(5)
    end
  end
end

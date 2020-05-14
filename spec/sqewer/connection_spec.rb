require_relative '../spec_helper'

describe Sqewer::Connection do
  describe '.default' do
    it 'returns a new LocalConnection if SQS_QUEUE_URL references sqlite:// as proto' do
      tf = Tempfile.new('sqlite-db')
      expect(ENV).to receive(:fetch).with('SQS_QUEUE_URL').and_return('sqlite3://' + tf.path)
      default = described_class.default
      expect(default).to be_kind_of(Sqewer::LocalConnection)
    end

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
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(double(failed: []))
      
      conn = described_class.new('https://fake-queue.com')
      expect(conn).to receive(:send_multiple_messages).and_call_original
      conn.send_message('abcdef')
    end
    
    it 'passes keyword args to Aws::SQS::Client' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(double(failed: []))
      
      conn = described_class.new('https://fake-queue.com')
      expect(conn).to receive(:send_multiple_messages).and_call_original
      conn.send_message('abcdef', delay_seconds: 5)
    end
    
    it 'retries on networking errors'
  end
  
  describe '#send_multiple_messages' do
    it 'sends 100 messages' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message_batch).exactly(11).times {|kwargs|
        expect(kwargs[:queue_url]).to eq("https://fake-queue.com")
        expect(kwargs[:entries]).to be_kind_of(Array)
        
        entries = kwargs[:entries]
        expect(entries.length).to be <= 10 # At most 10 messages per batch
        entries.each do | entry |
          expect(entry[:id]).to be_kind_of(String)
          expect(entry[:message_body]).to be_kind_of(String)
          expect(entry[:message_body]).to match(/Hello/)
        end
        double(failed: [])
      }
      
      conn = described_class.new('https://fake-queue.com')
      conn.send_multiple_messages do | b |
        102.times { b.send_message("Hello - #{SecureRandom.uuid}") }
      end
    end

    it 'regroups messages in batches to allow delivery if messages together are larger than 256KB of payload' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message_batch).exactly(4).times {|kwargs|
        expect(kwargs[:queue_url]).to eq("https://fake-queue.com")
        expect(kwargs[:entries]).to be_kind_of(Array)

        entries = kwargs[:entries]
        expect(entries.length).to eq(2)
        double(failed: [])
      }

      conn = described_class.new('https://fake-queue.com')
      string_of_128kb = "T" * (1024 * 128)
      conn.send_multiple_messages do | b |
        8.times { b.send_message(string_of_128kb) }
      end
    end

    it 'raises an exception if any message fails sending' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:send_message_batch) {|kwargs|
        double(failed: [double(message: 'Something went wrong at AWS', sender_fault: true)])
      }
      
      conn = described_class.new('https://fake-queue.com')
      expect {
        conn.send_multiple_messages do | b |
          10.times { b.send_message("Hello - #{SecureRandom.uuid}") }
        end
      }.to raise_error(/messages failed while doing send_message_batch with error:/)
    end

    it 'retries the message if it fails with a random AWS error' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      failed_response = double(failed: [double(message: 'Something went wrong at AWS', sender_fault: false, id: 0)])
      success_response = double(failed: [])
      # expect send_message to be called three times, the original one and two retries. The second retry succeeds.
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(failed_response,failed_response,success_response).exactly(3).times

      conn = described_class.new('https://fake-queue.com')
      conn.send_multiple_messages do | b |
        b.send_message("Hello - #{SecureRandom.uuid}")
      end
    end
    
    it 'retries on networking errors'
    
  end
  
  describe '#delete_message' do
    it 'deletes a single message'
  end
  
  describe '#delete_multiple_messages' do
    it 'deletes 100 messages' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:delete_message_batch).exactly(11).times {|kwargs|
        expect(kwargs[:queue_url]).to eq("https://fake-queue.com")
        expect(kwargs[:entries]).to be_kind_of(Array)
        
        entries = kwargs[:entries]
        expect(entries.length).to be <= 10 # At most 10 messages per batch
        entries.each do | entry |
          expect(entry[:id]).to be_kind_of(String)
          expect(entry[:receipt_handle]).to be_kind_of(String)
        end
        double(failed: [])
      }
      
      conn = described_class.new('https://fake-queue.com')
      conn.delete_multiple_messages do | b |
        102.times { b.delete_message(SecureRandom.uuid) }
      end
    end
    
    it 'raises an exception if any message fails sending' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      expect(fake_sqs_client).to receive(:delete_message_batch) {|kwargs|
        double(failed: [double(message: 'Something went wrong at AWS', sender_fault: true, id:1)])
      }
      
      conn = described_class.new('https://fake-queue.com')
      expect {
        conn.delete_multiple_messages do | b |
          102.times { b.delete_message(SecureRandom.uuid) }
        end
      }.to raise_error(/messages failed while doing delete_message_batch with error:/)
    end

    it 'retries the message if it fails with a random AWS error' do
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      failed_response = double(failed: [double(message: 'Something went wrong at AWS', sender_fault: false, id: 0)])
      success_response = double(failed: [])
      # expect send_message to be called three times, the original one and two retries. The second retry succeeds.
      expect(fake_sqs_client).to receive(:delete_message_batch).and_return(failed_response,failed_response,success_response).exactly(3).times

      conn = described_class.new('https://fake-queue.com')
      conn.delete_multiple_messages do | b |
        b.delete_message("Hello - #{SecureRandom.uuid}")
      end
    end
    
    it 'retries on networking errors'
  end
  
  describe '#receive_messages' do
    it 'uses the batched receive feature' do
      s = described_class.new('https://fake-queue')
      
      fake_sqs_client = double('Client')
      expect(Aws::SQS::Client).to receive(:new) { fake_sqs_client }
      
      fake_messages = (1..5).map {
        double(receipt_handle: SecureRandom.hex(4), body: SecureRandom.random_bytes(128), attributes: { 'attr' => 'val' })
      }
      fake_response = double(messages: fake_messages)
      
      expect(fake_sqs_client).to receive(:receive_message).with({:queue_url=>"https://fake-queue", :wait_time_seconds=>5, 
          :max_number_of_messages=>10}).and_return(fake_response)
      
      messages = s.receive_messages
      expect(messages.length).to eq(5)
    end
    
    it 'retries on networking errors'
  end
end

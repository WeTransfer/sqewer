require_relative '../spec_helper'

describe Sqewer::Connection do
  describe '.default' do
    it 'returns a new LocalConnection if SQS_QUEUE_URL references sqlite:// as proto' do
      tf = Tempfile.new('sqlite-db')
      stub_const('ENV', ENV.to_h.merge(
        'SQS_QUEUE_URL' => 'sqlite3://' + tf.path,
      ))

      default = described_class.default
      expect(default).to be_kind_of(Sqewer::LocalConnection)
    end

    it 'returns a new Connection with the SQS queue location picked from SQS_QUEUE_URL envvar' do
      stub_const('ENV', ENV.to_h.merge(
        'SQS_QUEUE_URL' => 'https://aws-fake-queue.com',
      ))

      default = described_class.default
      expect(default).to be_kind_of(described_class)
    end
  end

  describe 'using a singleton SQS client' do
    it 'uses a singleton sqs_client' do
      # we call this method to set the singleton client if it's not set yet
      Sqewer.client

      expect(Aws::SQS::Client).to_not receive(:new)
      expect(Sqewer.client).to receive(:send_message_batch).twice.and_return(double(failed: []))

      conn = described_class.new('https://fake-queue.com')
      conn.send_message('abcdef')

      conn = described_class.new('https://fake-queue2.com')
      conn.send_message('abcdef2')
    end
  end

  describe '#send_message' do
    it 'sends the message to the SQS client created with the URL given to the constructor' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(double(failed: []))

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      expect(conn).to receive(:send_multiple_messages).and_call_original
      conn.send_message('abcdef')
    end

    it 'passes keyword args to Aws::SQS::Client' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(double(failed: []))

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      expect(conn).to receive(:send_multiple_messages).and_call_original
      conn.send_message('abcdef', delay_seconds: 5)
    end

    it 'retries on networking errors'
  end

  describe '#send_multiple_messages' do
    it 'sends 100 messages' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
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

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      conn.send_multiple_messages do | b |
        102.times { b.send_message("Hello - #{SecureRandom.uuid}") }
      end
    end

    it 'regroups messages in batches to allow delivery if messages together are larger than 256KB of payload' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      expect(fake_sqs_client).to receive(:send_message_batch).exactly(4).times {|kwargs|
        expect(kwargs[:queue_url]).to eq("https://fake-queue.com")
        expect(kwargs[:entries]).to be_kind_of(Array)

        entries = kwargs[:entries]
        expect(entries.length).to eq(2)
        double(failed: [])
      }

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      string_of_128kb = "T" * (1024 * 128)
      conn.send_multiple_messages do | b |
        8.times { b.send_message(string_of_128kb) }
      end
    end

    it 'raises an exception if any message fails sending' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      expect(fake_sqs_client).to receive(:send_message_batch) {|kwargs|
        double(failed: [double(message: 'Something went wrong at AWS', sender_fault: true)])
      }

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      expect {
        conn.send_multiple_messages do | b |
          10.times { b.send_message("Hello - #{SecureRandom.uuid}") }
        end
      }.to raise_error(/messages failed while doing send_message_batch with error:/)
    end

    it 'retries the message if it fails with a random AWS error' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      failed_response = double(failed: [double(message: 'Something went wrong at AWS', sender_fault: false, id: 0)])
      success_response = double(failed: [])
      # expect send_message to be called three times, the original one and two retries. The second retry succeeds.
      expect(fake_sqs_client).to receive(:send_message_batch).and_return(failed_response,failed_response,success_response).exactly(3).times

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      conn.send_multiple_messages do | b |
        b.send_message("Hello - #{SecureRandom.uuid}")
      end
    end

    it 'retries on networking errors'

    [
      'Aws::Errors::MissingCredentialsError',
      'Aws::SQS::Errors::AccessDenied',
    ].each do |error_class_name|
      it "releases the sqs singleton client when AWS raises #{error_class_name}" do
        # We just want to assign the singleton client to test that it was released
        # in the end
        old_client = described_class.client
        expect(old_client).not_to be_nil

        # aws-sdk-sqs is loaded only after the method `.client`
        error_class = Object.const_get(error_class_name)

        fake_sqs_client = Aws::SQS::Client.new(stub_responses: true)
        fake_sqs_client.stub_responses(
          :send_message_batch,
          error_class.new(_context = nil, _message = nil)
        )

        conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
        expect do
          conn.send_multiple_messages do | b |
            b.send_message("Hello - #{SecureRandom.uuid}")
          end
        end.to raise_error(error_class)

        expect(described_class.client).not_to eq(old_client)
      end
    end
  end

  describe '#delete_message' do
    it 'deletes a single message'
  end

  describe '#delete_multiple_messages' do
    it 'deletes 100 messages' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
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

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      conn.delete_multiple_messages do | b |
        102.times { b.delete_message(SecureRandom.uuid) }
      end
    end

    it 'raises an exception if any message fails sending' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      expect(fake_sqs_client).to receive(:delete_message_batch) {|kwargs|
        double(failed: [double(message: 'Something went wrong at AWS', sender_fault: true, id:1)])
      }

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      expect {
        conn.delete_multiple_messages do | b |
          102.times { b.delete_message(SecureRandom.uuid) }
        end
      }.to raise_error(/messages failed while doing delete_message_batch with error:/)
    end

    it 'retries the message if it fails with a random AWS error' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      failed_response = double(failed: [double(message: 'Something went wrong at AWS', sender_fault: false, id: 0)])
      success_response = double(failed: [])
      # expect send_message to be called three times, the original one and two retries. The second retry succeeds.
      expect(fake_sqs_client).to receive(:delete_message_batch).and_return(failed_response,failed_response,success_response).exactly(3).times

      conn = described_class.new('https://fake-queue.com', client: fake_sqs_client)
      conn.delete_multiple_messages do | b |
        b.delete_message("Hello - #{SecureRandom.uuid}")
      end
    end

    it 'retries on networking errors'
  end

  describe '#receive_messages' do
    it 'uses the batched receive feature' do
      fake_sqs_client = instance_double(Aws::SQS::Client)
      s = described_class.new('https://fake-queue', client: fake_sqs_client)

      fake_messages = (1..5).map {
        double(receipt_handle: SecureRandom.hex(4), body: SecureRandom.random_bytes(128), attributes: { 'attr' => 'val' })
      }
      fake_response = double(messages: fake_messages)

      expect(fake_sqs_client).to receive(:receive_message).with(
        queue_url: "https://fake-queue",
        wait_time_seconds: 5,
        max_number_of_messages: 10,
        attribute_names: ['All']
      ).and_return(fake_response)
      messages = s.receive_messages
      expect(messages.length).to eq(5)
    end

    it 'retries on networking errors'

    [
      'Aws::Errors::MissingCredentialsError',
      'Aws::SQS::Errors::AccessDenied',
    ].each do |error_class_name|
      it "releases the sqs singleton client when AWS raises #{error_class_name}" do
        # We just want to assign the singleton client to test that it was released
        # in the end
        old_client = described_class.client
        expect(old_client).not_to be_nil

        # aws-sdk-sqs is loaded only after the method `.client`
        error_class = Object.const_get(error_class_name)

        fake_sqs_client = Aws::SQS::Client.new(stub_responses: true)
        fake_sqs_client.stub_responses(
          :receive_message,
          error_class.new(_context = nil, _message = nil)
        )

        expect do
          described_class.new('https://fake-queue', client: fake_sqs_client).receive_messages
        end.to raise_error(error_class)

        expect(described_class.client).not_to eq(old_client)
      end
    end
  end
end

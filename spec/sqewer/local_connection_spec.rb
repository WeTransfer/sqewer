require_relative '../spec_helper'

describe Sqewer::LocalConnection do
  around :each do |example|
    Dir.mktmpdir do |tmpdir_path|
      @tempdir_path = tmpdir_path
      example.run
    end
  end

  let(:temp_db_uri) { 'sqlite3:/%s/sqewer.sqlite3' % @tempdir_path }

  it 'honors the given database path and queue name' do
    Dir.mktmpdir do |tempdir_path|
      db_path = tempdir_path + '/test.sqlite3'
      qname = 'foobarbaz'
      uri_in_tempdir = 'sqlite3:/%s?queue=%s' % [db_path, qname]

      conn = described_class.new(uri_in_tempdir)
      conn.send_message("Hello!")

      db = SQLite3::Database.open(tempdir_path + '/test.sqlite3')
      expect(db.get_first_value('SELECT COUNT(id) FROM sqewer_messages_v3')).to eq(1)
      expect(db.get_first_value('SELECT queue_name FROM sqewer_messages_v3')).to eq('foobarbaz')
    end
  end

  it 'provides the attributes hash on the Message' do
    conn = described_class.new(temp_db_uri)
    conn.truncate!
    conn.send_multiple_messages do | b |
      b.send_message("Hello - #{SecureRandom.uuid}")
    end

    readback_message = conn.receive_messages.first
    expect(readback_message.attributes).to be_kind_of(Hash)
    expect(readback_message.attributes['SentTimestamp']).to be_kind_of(Integer)
  end

  it 'handles a full send/receive/delete cycle' do
    conn = described_class.new(temp_db_uri)
    conn.truncate!
    conn.send_multiple_messages do | b |
      4.times { b.send_message("Hello - #{SecureRandom.uuid}") }
    end

    messages = conn.receive_messages
    expect(messages.length).to eq(4)

    # Now the messages have become invisible
    messages = conn.receive_messages
    expect(messages.length).to eq(0)

    conn.delete_multiple_messages do | b |
      messages.each do |m|
        b.delete_message(m.id)
      end
    end

    messages = conn.receive_messages
    expect(messages).to be_empty
  end

  it 'is able to send from one process and receive from another' do
    conn = described_class.new(temp_db_uri)
    conn.truncate!

    producer_pid = fork do
      sleep 1.0
      conn.send_multiple_messages do | b |
        b.send_message("Hello from a producer co-process!")
      end
    end

    consumer_pid = fork do
      sleep 1.5
      msgs = conn.receive_messages
      exit(0) if msgs.length == 2
      raise "This is not what we expected. Received messages were #{msgs.inspect} but we really need 2 message to be there"
    end

    conn.send_multiple_messages do | b |
      b.send_message("Hello from parent!")
    end

    Process.wait(producer_pid)
    Process.wait(consumer_pid)
    expect($?.exitstatus).to eq(0)
  end
end

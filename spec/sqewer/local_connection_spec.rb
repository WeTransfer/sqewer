require_relative '../spec_helper'

describe Sqewer::LocalConnection do

  it 'handles a full send/receive/delete cycle' do
    conn = described_class.new('https://fake-queue.com')
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
end

class Sqewer::LocalConnection < Sqewer::Connection
  FAIL_AFTER_DELIVERIES = 10

  def with_db(**k)
    SQLite3::Database.open('sqewer-local-queue.sqlite3', **k) do |db|
      db.busy_timeout = 5
      return yield db
    end
  end

  def with_readonly_db(&blk)
    with_db(readonly: true, &blk)
  end

  def initialize(queue_url)
    require 'sqlite3'
    @queue_url = queue_url
    with_db do |db|
      db.execute("CREATE TABLE IF NOT EXISTS sqewer_messages_v1 (
        id INTEGER PRIMARY KEY AUTOINCREMENT ,
        queue_url VARCHAR NOT NULL,
        receipt_handle VARCHAR NOT NULL,
        deliver_after_epoch INTEGER,
        times_delivered_so_far INTEGER DEFAULT 0,
        last_delivery_at_epoch INTEGER,
        visible BOOLEAN DEFAULT 't',
        message_body TEXT)"
      )
      db.execute("CREATE INDEX IF NOT EXISTS index_sqewer_messages_v1_on_receipt_handle ON sqewer_messages_v1 (receipt_handle)")
      db.execute("CREATE INDEX IF NOT EXISTS index_sqewer_messages_v1_on_queue_url ON sqewer_messages_v1 (queue_url)")
    end
  rescue LoadError => e
    raise e, "You need the sqlite3 gem in your Gemfile to use LocalConnection. Add it to your Gemfile (`gem 'sqlite3'')"
  end

  # @return [Array<Message>] an array of Message objects 
  def receive_messages
    messages = load_receipt_handles_and_bodies
    messages.map {|message| Message.new(message[0], message[1]) }
  end

  # @yield [#send_message] the object you can send messages through (will be flushed at method return)
  # @return [void]
  def send_multiple_messages
    buffer = SendBuffer.new
    yield(buffer)
    messages = buffer.messages
    persist_messages(messages)
  end

  # Deletes multiple messages after they all have been succesfully decoded and processed.
  #
  # @yield [#delete_message] an object you can delete an individual message through
  # @return [void]
  def delete_multiple_messages
    buffer = DeleteBuffer.new
    yield(buffer)
    delete_persisted_messages(buffer.messages)
  end

  def truncate!
    with_db do |db|
      db.execute("DELETE FROM sqewer_messages_v1 WHERE queue_url = ?", @queue_url)
    end
  end

  private

  def delete_persisted_messages(messages)
    ids_to_delete = messages.map{|m| m.fetch(:receipt_handle) }
    with_db do |db|
      db.execute("BEGIN")
      ids_to_delete.each do |id|
        db.execute("DELETE FROM sqewer_messages_v1 WHERE receipt_handle = ?", id)
      end
      db.execute("COMMIT")
    end
  end

  def load_receipt_handles_and_bodies
    t = Time.now.to_i

    # First make messages that were previously marked invisible but not deleted visible again
    with_db do |db|
      db.execute("BEGIN")
      # Make messages visible that have to be redelivered
      db.execute("UPDATE sqewer_messages_v1
        SET visible = 't' 
        WHERE queue_url = ? AND visible = 'f' AND last_delivery_at_epoch < ?", @queue_url.to_s, t - 60)
      # Remove hopeless messages
      db.execute("DELETE FROM sqewer_messages_v1
        WHERE queue_url = ? AND times_delivered_so_far > ?", @queue_url.to_s, FAIL_AFTER_DELIVERIES)
      db.execute("COMMIT")
    end

    rows = with_readonly_db do |db|
      db.execute("SELECT id, receipt_handle, message_body FROM sqewer_messages_v1
        WHERE queue_url = ? AND visible = 't' AND deliver_after_epoch <= ? AND last_delivery_at_epoch <= ?",
        @queue_url.to_s, t, t)
    end
    
    with_db do |db|
      db.execute("BEGIN")
      rows.map do |(id, *_)|
        db.execute("UPDATE sqewer_messages_v1
          SET visible = 'f', times_delivered_so_far = times_delivered_so_far + 1, last_delivery_at_epoch = ?
          WHERE id = ?", t, id)
      end
      db.execute("COMMIT")
    end

    rows.map do |(_, *receipt_handle_and_body)|
      receipt_handle_and_body
    end
  end

  def persist_messages(messages)
    epoch = Time.now.to_i
    bodies_and_deliver_afters = messages.map do |msg|
      [msg.fetch(:message_body), epoch + msg.fetch(:delay_seconds, 0)]
    end

    with_db do |db|
      db.execute("BEGIN")
      bodies_and_deliver_afters.map do |body, deliver_after_epoch|
        db.execute("INSERT INTO sqewer_messages_v1
          (queue_url, receipt_handle, message_body, deliver_after_epoch, last_delivery_at_epoch)
          VALUES(?, ?, ?, ?, ?)",
          @queue_url.to_s, SecureRandom.uuid, body, deliver_after_epoch, epoch)
      end
      db.execute("COMMIT")
    end
  end
end

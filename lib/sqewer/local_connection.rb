require 'rack'
class Sqewer::LocalConnection < Sqewer::Connection
  ASSUME_DEADLETTER_AFTER_N_DELIVERIES = 10

  def self.parse_queue_url(queue_url_starting_with_sqlite3_proto)
    uri = URI.parse(queue_url_starting_with_sqlite3_proto)

    unless uri.scheme == 'sqlite3'
      raise "The scheme of the SQS queue URL should be with `sqlite3' but was %s" % uri.scheme
    end

    path_components = ['/', uri.hostname, uri.path].reject(&:nil?).reject(&:empty?).join('/').squeeze('/')
    dbfile_path = File.expand_path(path_components)

    queue_name = Rack::Utils.parse_nested_query(uri.query).fetch('queue', 'sqewer_local')

    [dbfile_path, queue_name]
  end

  def initialize(queue_url_with_sqlite3_scheme)
    require 'sqlite3'
    @db_path, @queue_name = self.class.parse_queue_url(queue_url_with_sqlite3_scheme)
    with_db do |db|
      db.execute("CREATE TABLE IF NOT EXISTS sqewer_messages_v3 (
        id INTEGER PRIMARY KEY AUTOINCREMENT ,
        queue_name VARCHAR NOT NULL,
        receipt_handle VARCHAR NOT NULL,
        deliver_after_epoch INTEGER,
        times_delivered_so_far INTEGER DEFAULT 0,
        last_delivery_at_epoch INTEGER,
        visible BOOLEAN DEFAULT 't',
        sent_timestamp_millis INTEGER,
        message_body TEXT)"
      )
      db.execute("CREATE INDEX IF NOT EXISTS on_receipt_handle ON sqewer_messages_v3 (receipt_handle)")
      db.execute("CREATE INDEX IF NOT EXISTS on_queue_name ON sqewer_messages_v3 (queue_name)")
    end
  rescue LoadError => e
    raise e, "You need the sqlite3 gem in your Gemfile to use LocalConnection. Add it to your Gemfile (`gem 'sqlite3'')"
  end

  # @return [Array<Message>] an array of Message objects
  def receive_messages
    load_receipt_handles_bodies_and_timestamps.map do |(receipt_handle, message_body, sent_timestamp_millis)|
      Message.new(receipt_handle, message_body, {'SentTimestamp' => sent_timestamp_millis})
    end
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

  # Only gets used in tests
  def truncate!
    with_db do |db|
      db.execute("DELETE FROM sqewer_messages_v3 WHERE queue_name = ?", @queue_name)
    end
  end

  private

  def with_db(**k)
    SQLite3::Database.open(@db_path, **k) do |db|
      db.busy_timeout = 5
      return yield db
    end
  rescue SQLite3::CantOpenException => e
    message_with_path = [e.message, 'at', @db_path].join(' ')
    raise SQLite3::CantOpenException.new(message_with_path)
  end

  def with_readonly_db(&blk)
    with_db(readonly: true, &blk)
  end

  def delete_persisted_messages(messages)
    ids_to_delete = messages.map{|m| m.fetch(:receipt_handle) }
    with_db do |db|
      db.execute("BEGIN")
      ids_to_delete.each do |id|
        db.execute("DELETE FROM sqewer_messages_v3 WHERE receipt_handle = ?", id)
      end
      db.execute("COMMIT")
    end
  end

  def load_receipt_handles_bodies_and_timestamps
    t = Time.now.to_i

    # First make messages that were previously marked invisible but not deleted visible again
    with_db do |db|
      db.execute("BEGIN")
      # Make messages visible that have to be redelivered
      db.execute("UPDATE sqewer_messages_v3
        SET visible = 't'
        WHERE queue_name = ? AND visible = 'f' AND last_delivery_at_epoch < ?", @queue_name.to_s, t - 60)
      # Remove hopeless messages
      db.execute("DELETE FROM sqewer_messages_v3
        WHERE queue_name = ? AND times_delivered_so_far >= ?", @queue_name.to_s, ASSUME_DEADLETTER_AFTER_N_DELIVERIES)
      db.execute("COMMIT")
    end

    # Then select messages to receive
    rows = with_readonly_db do |db|
      db.execute("SELECT id, receipt_handle, message_body, sent_timestamp_millis FROM sqewer_messages_v3
        WHERE queue_name = ? AND visible = 't' AND deliver_after_epoch <= ? AND last_delivery_at_epoch <= ?",
        @queue_name.to_s, t, t)
    end

    with_db do |db|
      db.execute("BEGIN")
      rows.map do |(id, *_)|
        db.execute("UPDATE sqewer_messages_v3
          SET visible = 'f', times_delivered_so_far = times_delivered_so_far + 1, last_delivery_at_epoch = ?
          WHERE id = ?", t, id)
      end
      db.execute("COMMIT")
    end

    rows.map do |(_db_id, receipt_handle, body, timestamp)|
      [receipt_handle, body, timestamp]
    end
  end

  def persist_messages(messages)
    epoch = Time.now.to_i
    sent_timestamp_millis = (Time.now.to_f * 1000).to_i
    bodies_and_deliver_afters = messages.map do |msg|
      [msg.fetch(:message_body), epoch + msg.fetch(:delay_seconds, 0)]
    end

    with_db do |db|
      db.execute("BEGIN")
      bodies_and_deliver_afters.map do |body, deliver_after_epoch|
        db.execute("INSERT INTO sqewer_messages_v3
          (queue_name, receipt_handle, message_body, deliver_after_epoch, last_delivery_at_epoch, sent_timestamp_millis)
          VALUES(?, ?, ?, ?, ?, ?)",
          @queue_name.to_s, SecureRandom.uuid, body, deliver_after_epoch, epoch, sent_timestamp_millis)
      end
      db.execute("COMMIT")
    end
  end
end

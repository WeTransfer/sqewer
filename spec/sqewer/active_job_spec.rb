require_relative '../spec_helper'
require 'securerandom'
require 'active_job'
require 'active_record'
require 'global_id'
require_relative '../../lib/sqewer/extensions/active_job_adapter'

class CreateFileJob < ActiveJob::Base
  def perform(file)
    File.open(file, 'w') {}
  end
end

class DeleteFileJob < ActiveJob::Base
  def perform(file)
    File.unlink(file)
  end
end

class ActivateUser < ActiveJob::Base
  def perform(user)
    user.active = true
    user.save!
  end
end

GlobalID.app = 'test-app'
class User < ActiveRecord::Base
  include GlobalID::Identification
end

describe ActiveJob::QueueAdapters::SqewerAdapter, :sqs => true do
  let(:file) { "#{Dir.mktmpdir}/file_active_job_test_1" }
  let(:client) { ::Aws::SQS::Client.new }

  after :all do
    # Ensure database files get killed afterwards
    File.unlink(ActiveRecord::Base.connection_config[:database]) rescue nil
  end

  before :all do
    ActiveJob::Base.queue_adapter = ActiveJob::QueueAdapters::SqewerAdapter

    test_seed_name = SecureRandom.hex(4)
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ('master_db_%s.sqlite3' % test_seed_name))

    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Schema.define(:version => 1) do
        create_table :users do |t|
          t.string :email, :null => true
          t.boolean :active, default: false
          t.timestamps :null => false
        end
      end
    end
  end

  before do
    @queue_url_hash = { queue_url: ENV['SQS_QUEUE_URL'] }
  end

  it "sends job to the queue" do
    CreateFileJob.perform_later(file)
    resp = client.get_queue_attributes(@queue_url_hash.merge(attribute_names: ["ApproximateNumberOfMessages"]))
    expect(resp.attributes["ApproximateNumberOfMessages"].to_i).to eq(1)
  end

  it "is correct format of serialized object in the queue" do
    job = CreateFileJob.perform_later(file)
    resp = client.receive_message(@queue_url_hash)
    serialized_job = JSON.parse(resp.messages.last.body)

    expect(serialized_job["_job_class"]).to eq("ActiveJob::QueueAdapters::SqewerAdapter::Performable")
    expect(serialized_job["_job_params"]["job"]["job_id"]).to eq(job.job_id)
  end

  it "executes job from the queue" do
    file_delayed = "#{file}_delayed"
    CreateFileJob.perform_later(file)
    CreateFileJob.perform_later(file_delayed)
    w = Sqewer::Worker.default
    w.start
    begin
      wait_for { File.exist?(file) }.to eq(true)
      File.unlink(file)
      DeleteFileJob.set(wait: 5.seconds).perform_later(file_delayed)
      wait_for { File.exist?(file_delayed) }.to eq(true)
      sleep 5
      expect(File.exist?(file_delayed)).to eq(false)
    ensure
      w.stop
    end
  end

  it "serializes and deserializes active record using GlobalID" do
    user = User.create(email: 'test@wetransfer.com')
    expect(user.active).to eq(false)
    ActivateUser.perform_later(user)
    w = Sqewer::Worker.default
    w.start
    sleep 4
    user.reload
    expect(user.active).to eq(true)
    w.stop
  end

end

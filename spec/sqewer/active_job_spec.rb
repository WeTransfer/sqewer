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

# Required so that the IDs for ActiveModel objects get generated correctly
GlobalID.app = 'test-app'

# Otherwise it is too talkative
ActiveJob::Base.logger = Sqewer::NullLogger

class User < ActiveRecord::Base
  include GlobalID::Identification
end

describe ActiveJob::QueueAdapters::SqewerAdapter, :sqs => true do

  before :each do
    # Rewire the queue to use SQLite
    @previous_queue_url = ENV['SQS_QUEUE_URL']
    ENV['SQS_QUEUE_URL'] = 'sqlite3:/%s/sqewer-temp.sqlite3' % Dir.pwd

    ActiveJob::Base.queue_adapter = ActiveJob::QueueAdapters::SqewerAdapter

    test_seed_name = SecureRandom.hex(4)
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: '%s/workdb.sqlite3' % Dir.pwd)

    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Schema.define(:version => 1) do
        create_table :users do |t|
          t.string :email, :null => true
          t.boolean :active, default: false
          t.timestamps :null => false
        end
      end
    end

    @worker = Sqewer::Worker.default
    @worker.start
  end

  after :each do
    ENV['SQS_QUEUE_URL'] = @previous_queue_url
    @worker.stop

    # Ensure database files get killed afterwards
    File.unlink(ActiveRecord::Base.connection_config[:database]) rescue nil
  end

  it "executes the CreateFileJob, both immediately and with a delay using set()" do
    wait_for { @worker.state }.to be_in_state(:running)

    tmpdir = Dir.mktmpdir
    CreateFileJob.perform_later(tmpdir + '/immediate')
    CreateFileJob.set(wait: 2.seconds).perform_later(tmpdir + '/delayed')

    wait_for { File.exist?(tmpdir + '/immediate') }.to eq(true)

    expect(File).not_to be_exist(tmpdir + '/delayed')

    wait_for { File.exist?(tmpdir + '/delayed') }.to eq(true)
  end

  it "switches the attribute on the given User" do
    wait_for { @worker.state }.to be_in_state(:running)

    user = User.create(email: 'test@wetransfer.com')
    expect(user.active).to eq(false)

    ActivateUser.perform_later(user)
    
    wait_for { user.reload.active? }.to eq(true)
  end
end

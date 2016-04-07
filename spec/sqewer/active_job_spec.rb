require_relative '../spec_helper'
require 'active_job'
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

describe ActiveJob::QueueAdapters::SqewerAdapter, :sqs => true do
  let(:file) { "#{Dir.mktmpdir}/file_active_job_test_1" }
  let(:client) { ::Aws::SQS::Client.new }

  before do
    ActiveJob::Base.queue_adapter = ActiveJob::QueueAdapters::SqewerAdapter
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

end

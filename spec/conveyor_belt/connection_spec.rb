require_relative '../spec_helper'

describe ConveyorBelt::Connection do
  describe '.default' do
    it 'returns a new Connection with the SQS queue location picked from SQS_QUEUE_URL envvar'
  end
  
  describe '#send_message' do
    it 'sends the message to the SQS client created with the URL given to the constructor'
    it 'passes keyword args to Aws::SQS::Client'
  end
  
  describe 'poll' do
    it 'uses the batched receive feature'
  end
end

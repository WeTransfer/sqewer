require_relative '../spec_helper'
require_relative '../../lib/sqewer/extensions/appsignal_wrapper.rb'

# Needed because the wrapper won't initalize itself unless Appsignal is defined
class Appsignal
end

describe Sqewer::Contrib::AppsignalWrapper do
  describe '#set_transaction_details_from_job' do
    it 'uses class_name method if it is available' do
      job = double('job')
      txn = double('transaction')
      allow(txn).to receive(:set_action)
      allow(txn).to receive_message_chain(:request,:params=)
      allow(job).to receive(:to_h).and_return({})
      expect(job).to receive(:respond_to?).twice.and_return(true)
      expect(job).to receive(:class_name).and_return('biep')
      Sqewer::Contrib::AppsignalWrapper.new.set_transaction_details_from_job(txn, job)
    end

    it 'falls back to class.to_s if it has no class_name method' do
      job = double('job')
      txn = double('transaction')
      allow(txn).to receive(:set_action)
      allow(txn).to receive_message_chain(:request,:params=)
      expect(job).to receive(:respond_to?).twice.and_return(false)
      expect(job).to receive(:class).and_return('biep')
      Sqewer::Contrib::AppsignalWrapper.new.set_transaction_details_from_job(txn, job)
    end
  end
end

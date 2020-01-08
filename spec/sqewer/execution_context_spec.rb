require_relative '../spec_helper'

describe Sqewer::ExecutionContext do
  it 'offers a submit! that goes through the given Submitter argument' do
    fake_submitter = double('Submitter')
    
    expect(fake_submitter).to receive(:submit!).with(:fake_job, any_args)
    subject = described_class.new(fake_submitter)
    subject.submit!(:fake_job)
  end
  
  it 'offers arbitrary key/value storage' do
    fake_submitter = double('Submitter')
    subject = described_class.new(fake_submitter)
    
    subject['foo'] = 123
    expect(subject['foo']).to eq(123)
    expect(subject[:foo]).to eq(123)
    expect(subject.fetch(:foo)).to eq(123)
    
    expect {
      subject.fetch(:bar)
    }.to raise_error(KeyError)
    
    default_value = subject.fetch(:bar) { 123 }
    expect(default_value).to eq(123)
  end
  
  it 'returns the NullLogger from #logger if no logger was passed to the constructor' do
    fake_submitter = double('Submitter')
    
    subject = described_class.new(fake_submitter)
    expect(subject.logger).to eq(Sqewer::NullLogger)
  end
  
  it 'offers access to the given "logger" extra param if it was given to the constructor' do
    fake_submitter = double('Submitter')
    fake_logger = double('Logger')
    
    subject = described_class.new(fake_submitter, {'logger' => fake_logger})
    expect(subject.logger).to eq(fake_logger)
  end
end

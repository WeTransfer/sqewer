require_relative 'spec_helper'

describe Sqewer do
  it 'provides a #submit!() method that is a shortcut to the default submitter' do
    fake_submitter = double('Submitter')
    expect(Sqewer::Submitter).to receive(:default) { fake_submitter }
    
    first_job = double('Job1')
    second_job = double('Job2')
    
    expect(fake_submitter).to receive(:submit!).with(first_job, second_job, any_args)
    Sqewer.submit!(first_job, second_job)
  end
end

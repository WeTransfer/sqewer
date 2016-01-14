require_relative '../spec_helper'

describe ConveyorBelt::AtomicCounter do
  it 'is atomic' do
    c = described_class.new
    expect(c.to_i).to be_zero
    
    threads = (1..64).map do
      Thread.new { sleep(rand); c.increment! }
    end
    threads.map(&:join)
    
    expect(c.to_i).to eq(threads.length)
  end
end

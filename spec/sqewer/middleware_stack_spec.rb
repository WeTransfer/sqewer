require_relative '../spec_helper'

describe Sqewer::MiddlewareStack do
  it 'returns a default instance' do
    stacks = (1..100).map { described_class.default }
    expect(stacks.uniq.length).to eq(1)
  end
  
  describe '#around_deserialization' do
    it 'works without any handlers added' do
      stack = described_class.new
      prepare_result = stack.around_deserialization(nil, 'msg-123', '{"body":"some text"}', { 'attr' => 'val' }) { :prepared }
      expect(prepare_result).to eq(:prepared)
    end
    
    it 'works with an entire stack' do
      called = []
      handler = double('Some middleware')
      allow(handler).to receive(:around_deserialization){|*a, &blk|
        called << a
        blk.call 
      } 
      
      stack = described_class.new
      stack << handler
      stack << double('Object that does not handle around_deserialization')
      stack << handler
      stack << handler
      result = stack.around_deserialization(nil, 'msg-123', '{"body":"some text"}', { 'attr' => 'val' }) { :foo }
      expect(result).to eq(:foo)
      expect(called).not_to be_empty
      
      expect(called).to eq([
          [nil, "msg-123", "{\"body\":\"some text\"}", { 'attr' => 'val' }],
          [nil, "msg-123", "{\"body\":\"some text\"}", { 'attr' => 'val' }],
          [nil, "msg-123", "{\"body\":\"some text\"}", { 'attr' => 'val' }]]
      )
    end
  end
  
  describe '#around_execution' do
    it 'works without any handlers added' do
      stack = described_class.new
      prepare_result = stack.around_execution(nil, nil) { :prepared }
      expect(prepare_result).to eq(:prepared)
    end
    
    it 'works with an entire stack' do
      called = []
      handler = double('Some middleware')
      allow(handler).to receive(:around_execution){|*a, &blk|
        called << a
        blk.call
      } 
      
      stack = described_class.new
      stack << handler
      stack << handler
      stack << double('Object that does not handle around_execution')
      stack << handler
      
      result = stack.around_execution(:some_job, :some_context) { :executed }
      expect(result).to eq(:executed)
      expect(called).not_to be_empty
      
      expect(called).to eq([[:some_job, :some_context], [:some_job, :some_context], [:some_job, :some_context]])
    end
  end
end

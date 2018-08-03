require_relative '../spec_helper'

describe Sqewer::SimpleJob do
  it 'raises a clear error for an unknown attribute' do
    example_class = Class.new do
      attr_accessor :foo, :bar
      include Sqewer::SimpleJob
    end
    
    expect {
      example_class.new(zoo: 1, bar: 2)
    }.to raise_error(/Unknown attribute \:zoo for/)
  end
  
  it 'uses defined accessors to provide decent string representation' do
    example_class = Class.new do
      attr_accessor :foo, :bar
      include Sqewer::SimpleJob
    end
    
    job = example_class.new(foo: 1, bar: 2)
    expect(job.inspect).to include('Class')
    expect(job.inspect).to include(':foo=>1')
    expect(job.inspect).to include(':bar=>2')
  end
  
  it 'uses inspectable_attributes to limit the scope of .inspect' do
    example_class = Class.new do
      attr_accessor :foo, :bar
      def inspectable_attributes
        [:foo]
      end
      include Sqewer::SimpleJob
    end
    
    job = example_class.new(foo: 1, bar: 2)
    expect(job.inspect).to include('Class')
    expect(job.inspect).to include('{:foo=>1}')
    expect(job.inspect).not_to include('bar')
  end
  
  it 'provides for a keyword argument constructor and a to_h method' do
    example_class = Class.new do
      attr_accessor :foo, :bar
      include Sqewer::SimpleJob
    end
    
    string_repr = example_class.to_s
    
    new_instance = example_class.new(foo: 1, bar: 2)
    
    expect(new_instance.foo).to eq(1)
    expect(new_instance.bar).to eq(2)
    
    hash_repr = new_instance.to_h
    expect(hash_repr).to eq({foo: 1, bar: 2})
  end
  
  
  it 'raises if arguments are forgotten' do
    example_class = Class.new do
      attr_accessor :foo, :bar
      include Sqewer::SimpleJob
    end
    
    expect {
      example_class.new(foo: 1)
    }.to raise_error('Missing job attribute :bar')
  end
end

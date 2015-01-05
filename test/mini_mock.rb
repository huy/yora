class MiniMockSink
  def initialize
    @args_called = []
  end

  attr_reader :args_called

  def args
    fail 'More than one call' if @args_called.size > 1
    @args_called.first
  end

  def called(args)
    @args_called << args
  end

  def times_called
    @args_called.size
  end

  def called?
    !@args_called.empty?
  end
end

class Object
  def mock(method)
    sink = MiniMockSink.new

    m = (class << self; self; end)

    m.send :define_method, method do |*args, &blk|
      args << blk if blk
      sink.called args
    end

    sink
  end
end

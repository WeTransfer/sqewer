module Sqewer::RetriableJob

  module TerminalError; end
  module RetriableError; end

  class Hopeless < StandardError
    include TerminalError
  end

  class ObjectMissing < StandardError
    include TerminalError
  end

  def self.included(into)
    into.send(:attr_accessor, :retries)
    super
  end

  def inspectable_attributes
    super + [:retries]
  end

  # Provides the default constructor that sets retries: to 0. When the job is re-executed
  # the retries will be present in the job arguments and will be > 0 automatically.
  def initialize(retries: 0, **jobargs)
    super
  end

  # Retry this job. Will also increase the retries parameter before submitting.
  def retry_or_fail!(via_executor, max_retries, **kwargs)
    raise Hopeless, "Maximum retries reached (#{retries})" if retries > max_retries
    retry!(via_executor, **kwargs)
  end

  # Retry this job. Will also increase the retries parameter before submitting.
  def retry!(via_executor, delay_seconds: 1)
    self.retries += 1
    via_executor.submit!(self, delay_seconds: delay_seconds)
  end
end

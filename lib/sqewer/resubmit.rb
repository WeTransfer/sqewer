module Sqewer
  class Resubmit
    attr_reader :job
    attr_reader :execute_after
    
    def initialize(job_to_resubmit, execute_after_timestamp)
      @job = job_to_resubmit
      @execute_after = execute_after_timestamp
    end
    
    def run(ctx)
      # Take the maximum delay period SQS allows
      required_delay = (@execute_after - Time.now.to_i)
      ctx.submit!(@job, delay_seconds: required_delay)
    end
  end
end

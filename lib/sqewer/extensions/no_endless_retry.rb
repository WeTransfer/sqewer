module Sqewer
  # Can be used as a wrapper middleware in an ExecutionContext to
  # rescue and log terminal errors.
  class NoEndlessRetry
    def around_execution(job, context)
      yield
    rescue Sqewer::TerminalError => e
      # This job can be deleted as there is no point in trying anymore
      Sqewer::Worker.logger.fatal { "Discarding a job: #{e.class}/#{e.message}" }
    end
  end
end

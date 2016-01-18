An AWS SQS-based queue processor, for highly distributed job engines.

## The shortest introduction possible

In your environment, set `SQS_QUEUE_URL`. Then, define a job class:

    class MyJob
      def run
       File.open('output', 'a') { ... }
      end
    end

Then submit the job:

    Sqewer.submit!(MyJob.new)

and to start processing, in your commandline handler:

    #!/usr/bin/env ruby
    require 'my_applicaion'
    Sqewer::CLI.run

To add arguments to the job

    class JobWithArgs
      include Sqewer::SimpleJob
      attr_accessor :times
      
      def run
        ...
      end
    end
    ...
    Sqewer.submit!(JobWithArgs.new(times: 20))

Submitting jobs from other jobs (the job will go to the same queue the parent job came from):

    class MyJob
      def run(worker_context)
        ...
        worker_context.submit!(CleanupJob.new)
      end
    end

The messages will only be deleted from SQS once the job execution completes without raising an exception.

## Detailed usage instructions

For more detailed usage information, see [DETAILS.md](./DETAILS.md)

## Frequently asked questions (A.K.A. _why is it done this way_)

Please see [FAQ.md](./FAQ.md). This might explain some decisions behind the library in greater detail.
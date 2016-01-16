Conveyor Belt is an SQS based queue processor.

## The shortest introduction possible

In your environment, set `SQS_QUEUE_URL`. Then, define a job class:

    class MyJob
      def run
       File.open('output', 'a') { ... }
      end
    end

Then submit the job:

    ConveyorBelt.submit!(MyJob.new)

and to start processing, in your commandline handler:

    #!/usr/bin/env ruby
    require 'my_applicaion'
    ConveyorBelt::CLI.run

To add arguments to the job

    class JobWithArgs
      include ConveyorBelt::SimpleJob
      attr_accessor :times
      
      def run
        ...
      end
    end
    ...
    ConveyorBelt.submit!(JobWithArgs.new(times: 20))

Submitting jobs from other jobs (the job will go to the same queue the parent job came from):

    class MyJob
      def run(worker_context)
        ...
        worker_context.submit!(CleanupJob.new)
      end
    end

The messages will only be deleted from SQS once the job execution completes without raising an exception.

For more detailed usage information, see [DETAILS.md](./DETAILS.md)
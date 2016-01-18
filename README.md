An AWS SQS-based queue processor, for highly distributed job engines.

[![Build Status](https://travis-ci.org/WeTransfer/sqewer.svg?branch=master)](https://travis-ci.org/WeTransfer/sqewer)

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
    Sqewer::CLI.start

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

## Requirements

Ruby 2.1+, version 2 of the AWS SDK.

## Detailed usage instructions

For more detailed usage information, see [DETAILS.md](./DETAILS.md)

## Frequently asked questions (A.K.A. _why is it done this way_)

Please see [FAQ.md](./FAQ.md). This might explain some decisions behind the library in greater detail.

## Contributing to the library
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Run your tests against a _real_ SQS queue. You will need your tests to have permissions to create and delete SQS queues.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright (c) 2016 WeTransfer. See LICENSE.txt for further details.


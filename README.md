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

Ruby 2.6+, version 2 of the AWS SDK. You can also run Sqewer backed by a SQLite database file, which can be handy for development situations.

## Job storage

Jobs are (by default) stored in SQS as JSON blobs. A very simple job ticket looks like this:

    {"_job_class": "MyJob", "_job_params": null}

When this ticket is being picked up by the worker, the worker will do the following:

    job = MyJob.new
    job.run

So the smallest job class has to be instantiatable, and has to respond to the `run` message.

## Jobs with arguments and parameters

Job parameters can be passed as keyword arguments. Properties in the job ticket (encoded as JSON) are
directly translated to keyword arguments of the job constructor. With a job ticket like this:

    {
      "_job_class": "MyJob",
      "_job_params": {"ids": [1,2,3]}
    }

the worker will instantiate your `MyJob` class with the `ids:` keyword argument:

    job = MyJob.new(ids: [1,2,3])
    job.run

Note that at this point only arguments that are raw JSON types are supported:

* Hash
* Array
* Numeric
* String
* nil/false/true

If you need marshalable Ruby types there instead, you might need to implement a custom `Serializer.`

### Sqewer::SimpleJob

The module `Sqewer::SimpleJob` can be included to a job class to add some features, specially dealing with attributes, see more details [here](https://github.com/WeTransfer/sqewer/blob/master/lib/sqewer/simple_job.rb).

## Jobs spawning dependent jobs

If your `run` method on the job object accepts arguments (has non-zero `arity` ) the `ExecutionContext` will
be passed to the `run` method.

    job = MyJob.new(ids: [1,2,3])
    job.run(execution_context)

The execution context has some useful methods:

 * `logger`, for logging the state of the current job. The logger messages will be prefixed with the job's `inspect`.
 * `submit!` for submitting more jobs to the same queue

A job submitting a subsequent job could look like this:

    class MyJob
      def run(ctx)
        ...
        ctx.submit!(DeferredCleanupJob.new)
      end
    end

## Job submission

In general, a job object that needs some arguments for instantiation must return a Hash from it's `to_h` method. The hash must
include all the keyword arguments needed to instantiate the job when executing. For example:

    class SendMail
      def initialize(to:, body:)
        ...
      end

      def run()
        ...
      end

      def to_h
        {to: @to, body: @body}
      end
    end

Or if you are using simple Struct you could inherit your Job from it:

    class SendMail < Struct.new(:to, :body, keyword_init: true)
      def run
        ...
      end
    end

## Job marshaling

By default, the jobs are converted to JSON and back from JSON using the Sqewer::Serializer object. You can
override that object if you need to handle job tickets that come from external sources and do not necessarily
conform to the job serialization format used internally. For example, you can handle S3 bucket notifications:

    class CustomSerializer < Sqewer::Serializer
      # Overridden so that we can instantiate a custom job
      # from the AWS notification payload.
      # Return "nil" and the job will be simply deleted from the queue
      def unserialize(message_blob)
        message = JSON.load(message_blob)
        return if message['Service'] # AWS test
        return HandleS3Notification.new(message) if message['Records']

        super # as default
      end
    end

Or you can override the serialization method to add some metadata to the job ticket on job submission:

    class CustomSerializer < Sqewer::Serializer
      def serialize(job_object)
        json_blob = super
        parsed = JSON.load(json_blob)
        parsed['_submitter_host'] = Socket.gethostname
        JSON.dump(parsed)
      end
    end

If you return `nil` from your `unserialize` method the job will not be executed,
but will just be deleted from the SQS queue.

## Starting and running the worker

The very minimal executable for running jobs would be this:

    #!/usr/bin/env ruby
    require 'my_applicaion'
    Sqewer::CLI.start

This will connect to the queue at the URL set in the `SQS_QUEUE_URL` environment variable, and
use all the default parameters. The `CLI` module will also set up a signal handler to terminate
the current jobs cleanly if the commandline app receives a USR1 and TERM.

You can also run a worker without signal handling, for example in test
environments. Note that the worker is asynchronous, it has worker threads
which do all the operations by themselves.

    worker = Sqewer::Worker.new
    worker.start
    # ...and once you are done testing
    worker.stop

## Configuring the worker

One of the reasons this library exists is that sometimes you need to set up some more
things than usually assumed to be possible. For example, you might want to have a special
logging library:

    worker = Sqewer::Worker.new(logger: MyCustomLogger.new)

Or you might want a different job serializer/deserializer (for instance, if you want to handle
S3 bucket notifications coming into the same queue):

    worker = Sqewer::Worker.new(serializer: CustomSerializer.new)

You can also elect to inherit from the `Worker` class and override some default constructor
arguments:

    class CustomWorker < Sqewer::Worker
      def initialize(**kwargs)
        super(serializer: CustomSerializer.new, ..., **kwargs)
      end
    end

The `Sqewer::CLI` module that you run from the commandline handler application can be
started with your custom Worker of choice:

    custom_worker = Sqewer::Worker.new(logger: special_logger)
    Sqewer::CLI.start(custom_worker)

## Threads versus processes

sqewer uses threads. If you need to run your job from a forked subprocess (primarily for memory
management reasons) you can do so from the `run` method. Note that you might need to apply extra gymnastics
to submit extra jobs in this case, as it is the job of the controlling worker thread to submit the messages
you generate. For example, you could use a pipe. But in a more general case something like this can be used:

    class MyJob
      def run
        pid = fork do
          SomeRemoteService.reconnect # you are in the child process now
          ActiveRAMGobbler.fetch_stupendously_many_things.each do |...|
          end
        end

        _, status = Process.wait2(pid)

        # Raise an error in the parent process to signal Sqewer that the job failed
        # if the child exited with a non-0 status
        raise "Child process crashed" unless status.exitstatus && status.exitstatus.zero?
      end
    end

## Execution and serialization wrappers (middleware)

You can wrap job processing in middleware. A full-featured middleware class looks like this:

    class MyWrapper
      # Surrounds the job instantiation from the string coming from SQS.
      def around_deserialization(serializer, msg_id, msg_payload, msg_attributes)
        # msg_id is the receipt handle, msg_payload is the message body string, msg_attributes are the message's attributes
        yield
      end

      # Surrounds the actual job execution
      def around_execution(job, context)
        # job is the actual job you will be running, context is the ExecutionContext.
        yield
      end
    end

You need to set up a `MiddlewareStack` and supply it to the `Worker` when instantiating:

    stack = Sqewer::MiddlewareStack.new
    stack << MyWrapper.new
    w = Sqewer::Worker.new(middleware_stack: stack)

# Execution guarantees

As a queue worker system, Sqewer makes a number of guarantees, which are as solid as the Ruby's
`ensure` clause.

  * When a job succeeds (raises no exceptions), it will be deleted from the queue
  * When a job submits other jobs, and succeeds, the submitted jobs will be sent to the queue
  * When a job, or any wrapper routing of the job execution,
    raises any exception, the job will not be deleted
  * When a submit spun off from the job, or the deletion of the job itself,
    cause an exception, the job will not be deleted

Use those guarantees to your advantage. Always make your jobs horizontally repeatable (if two hosts
start at the same job at the same time), idempotent (a job should be able to run twice without errors),
and traceable (make good use of logging).

# Usage with Rails via ActiveJob

This gem includes a queue adapter for usage with ActiveJob in Rails 5+. The functionality
is well-tested and should function for any well-conforming ActiveJob subclasses.

To run the default `sqewer` worker setup against your Rails application, first set it as the
executing backend for ActiveJob in your Rails app configuration, set your `SQS_QUEUE_URL`
in the environment variables, and make sure you can access it using your default (envvar-based
or machine role based) AWS credentials. Then, set sqewer as the adapter for ActiveJob:

    class Application < Rails::Application
      ...
      config.active_job.queue_adapter = :sqewer
    end

and then run

    $ bundle exec sqewer_rails

in your rails source tree, via a foreman Procfile or similar. If you want to run your own worker binary
for executing the jobs, be aware that you _have_ to eager-load your Rails application's code explicitly
before the Sqewer worker is started. The worker is threaded and any kind of autoloading does not generally
play nice with threading. So do not forget to add this in your worker code:

    Rails.application.eager_load!

For handling error reporting within your Sqewer worker, set up a middleware stack as described in the documentation.

## ActiveJob feature support matrix

Compared to the matrix of features as seen in the
[official ActiveJob documentation](http://edgeapi.rubyonrails.org/classes/ActiveJob/QueueAdapters.html)
`sqewer` has the following support for various ActiveJob options, in comparison to the builtin
ActiveJob adapters:

    |                   | Async | Queues | Delayed    | Priorities | Timeout | Retries |
    |-------------------|-------|--------|------------|------------|---------|---------|
    | sqewer            | Yes   | No     | Yes        | No         | No      | Global  |
    |       //          |  //   |  //    |  //        | //         |  //     | //      |
    | Active Job Async  | Yes   | Yes    | Yes        | No         | No      | No      |
    | Active Job Inline | No    | Yes    | N/A        | N/A        | N/A     | N/A     |

Retries are set up globally for the entire SQS queue. There is no specific queue setting per job,
since all the messages go to the queue available to `Sqewer.submit!`.

There is no timeout handling, if you need it you may want to implement it within your jobs proper.
Retries are handled on Sqewer level for as many deliveries as your SQS settings permit.

## Delay handling

Delayed execution is handled via a combination
of the `delay_seconds` SQS parameter and the `_execute_after` job key (see the serializer documentation
in Sqewer for more). In a nutshell - if you postpone a job by less than 900 seconds, the standard delivery
delay option will be used - and the job will become visible for workers on the SQS queue only after this period.

If a larger delay is used, the job will receive an additional field called `_execute_after`, which will contain
a UNIX timestamp in seconds of when it must be executed at the earliest. In addition, the maximum permitted SQS
delivery delay will be set for it. If the job then gets redelivered, Sqewer will automatically put it back on the
queue with the same maximum delay, and will continue doing so for as long as necessary.

Note that this will incur extra receives and sends on the queue, and even though it is not substantial,
it will not be free. We think that this is an acceptable workaround for now, though. If you want a better approach,
you may be better off using a Rails scheduling system and use a cron job or similar to spin up your enqueue
for the actual, executable background task.

# Frequently asked questions (A.K.A. _why is it done this way_)

This document tries to answer some questions that may arise when reading or using the library. Hopefully
this can provide some answers with regards to how things are put together.

## Why separate `new` and `run` methods instead of just `perform`?

Because the job needs access to the execution context of the worker. It turned out that keeping the context
in global/thread/class variables was somewhat nasty, and jobs needed access to the current execution context
to enqueue the subsequent jobs, and to get access to loggers (and other context-sensitive objects). Therefore
it makes more sense to offer Jobs access to the execution context, and to make a Job a command object.

Also, Jobs usually use their parameters in multiple smaller methods down the line. It therefore makes sense
to save those parameters in instance variables or in struct members.

## Why keyword constructors for jobs?

Because keyword constructors map very nicely to JSON objects and provide some (at least rudimentary) arity safety,
by checking for missing keywords and by allowing default keyword argument values. Also, we already have some
products that use those job formats. Some have dozens of classes of jobs, all with those signatures and tests.

## Why no weighted queues?

Because very often when you want to split queues servicing one application it means that you do not have enough
capacity to serve all of the job _types_ in a timely manner. Then you try to assign priority to separate jobs,
whereas in fact what you need are jobs that execute _roughly_ at the same speed - so that your workers do not
stall when clogged with mostly-long jobs. Also, multiple queues introduce more configuration, which, for most
products using this library, was a very bad idea (more workload for deployment).

## Why so many configurable components?

Because sometimes your requirements differ just-a-little-bit from what is provided, and you have to swap your
implementation in instead. One product needs foreign-submitted SQS jobs (S3 notifications). Another product
needs a custom Logger subclass. Yet another product needs process-based concurrency on top of threads.
Yet another process needs to manage database connections when running the jobs. Have 3-4 of those, and a
pretty substantial union of required features will start to emerge. Do not fear - most classes of the library
have a magic `.default` method which will liberate you from most complexities.

## Why multithreading for workers?

Because it is fast and relatively memory-efficient. Most of the workload we encountered was IO-bound or even
network-IO bound. In that situation it makes more sense to use threads that switch quickly, instead of burdening
the operating system with too many processes. An optional feature for one-process-per-job is going to be added
soon, for tasks that really warrant it (like image manipulation). For now, however, threads are working quite OK.

## Why no Celluloid?

Because I found that a producer-consumer model with a thread pool works quite well, and can be created based on
the Ruby standard library alone.

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


A more in-depth explanation of the systems below.

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

Or if you are using `ks` gem (https://rubygems.org/gems/ks) you could inherit your Job from it:

    class SendMail < Ks.strict(:to, :body)
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
    Sqewer::CLI.run

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
        super(serializer: CustomSerializer.mnew, ..., **kwargs)
      end
    end

The `Sqewer::CLI` module that you run from the commandline handler application can be
started with your custom Worker of choice:

    custom_worker = Sqewer::Worker.new(logger: special_logger)
    Sqewer::CLI.start(custom_worker)

## Threads versus processes

You can elect to use process isolation per job. Each job will then run in a forked process, on which
the main worker process will `wait()`. To do so, pass `Sqewer::Isolator.process` as the `isolator:`
option to the Worker

    proc_worker = Sqewer::Worker.new(isolator: Sqewer::Isolator.process)

By default the system is working with threads only, as processes obviously have some overhead.

## Execution and serialization wrappers (middleware)

You can wrap job processing in middleware. A full-featured middleware class looks like this:

    class MyWrapper
      # Surrounds the job instantiation from the string coming from SQS.
      def around_deserialization(serializer, msg_id, msg_payload)
        # msg_id is the receipt handle, msg_payload is the message body string
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
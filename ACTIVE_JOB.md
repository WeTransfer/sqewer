# Sqewer with ActiveJob

This gem includes a queue adapter for usage with ActiveJob in Rails 4.2+. The functionality
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

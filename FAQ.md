# FAQ

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


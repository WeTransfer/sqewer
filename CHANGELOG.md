### 6.4.0
- Raise an exception in submit! if the job serializes to a message that is
  above the native SQS limit for message size.
- Ensure SendMessageBatch is only performed for batches totaling 256KB of message size or less.
- Insert Sqewer::Error between StandardError and our custom errors for easier rescuing

### 6.3.0
- Add support for Ruby 2.7

### 6.2.2
- Test the Appsignal integration using actual Appsignal libraries
- In the Appsignal integration, replace a call of `set_queue_start=` with `set_queue_start`

### 6.2.1
- Appsignal queue start time should be set as an Integer of milliseconds, not as a Time object

### 6.2.0
- Store SentTimestamp in SQLite and restore it on execution

### 6.1.0
- Pass SQS message attributes through the middleware chain
- Recover the SentTimestamp attribute and set it as queue start in Appsignal
- Make sure a job given to `submit!` responds to `run`

### 6.0.6
- Make sure :sqewer ActiveJob adapter parameter works in both Rails 4
  and Rails 5.

### 6.0.5
- Limit ActiveJob compatibility to 4.2 and later, and add Travis test
  setup for multiple Ruby versions and Rails versions up to and including 5.1

### 6.0.4
- If running on an AWS EC2 instance and retrieving AWS credentials from the instance metadata, Sqewer will now retry up to five times if the instance metadata are not available. This fixes intermittent `Aws::Errors::MissingCredentialsError` exceptions.

### 6.0.3
- It is now no longer required to have ActiveJob loaded when integrating with Appsignal.

### 6.0.2
- Fix an issue in the interaction in the Activejob extension that caused all the background jobs to show up as instances of `#run`.

### 6.0.1
- Fix an issue in the interaction between the Appsignal and Activejob extensions that caused all the background jobs to show up as instances of `ActiveJob::QueueAdapters::SqewerAdapter::Performable#run`.

### 6.0.0
- Bump the supported AWS SDK to v3 and only require `aws-sdk-sqs` as a dependency. This reduces the amount of code Sqewer needs to load, as SQS is the only service we are actually using. This requires the hosting application to be updated to the SDK v3 as well.
- Reduce spurious test failures when testing the ActiveJob adapter

### 5.1.1
- Add support for local SQLite-based queues, that can be used by starting the SQS_QUEUE_URL with `sqlite3:/`. This decouples sqewer from the AWS SDK and allows one to develop without needing the entire AWS stack or it's simulation environments such as fake_sqs. The SQLite database can be safely used across multiple processes.

### 5.0.9
- Testing with fake_sqs when the daemon was not running or with a misconfigured SQS_QUEUE_URL could lead to Sqewer seemingly hanging. The actual cause was a _very_ large amount of retries were being performed. The amount of retries has been adjusted to a more reasonable number.
- An exception in the message fetching thread could lead to the receiving thread silently dying, while leaving the worker threads running without any work to do. Uncaught exceptions in the receiving thread now lead to a graceful shutdown of the worker.

### 5.0.8
- Retry sending and deleting messages when `sender_fault=false`.

### 5.0.7
- Report errors with string interpolation to avoid confusion.
- Fix failure when running one test at a time.

### 5.0.6
- Additional change to error reporting: report errors both on submitting and on deleting messages.

### 2017-05-03
- Released v5.0.5 to Rubygems.org.
- Added CHANGELOG.md (you're reading it!).

### 2017-05-01
- Tiny change to improve error reporting; the error message from AWS when submitting to the queue is sometimes empty so we call .inspect on it.

### 2017-03-11
- Released v5.0.4 to Rubygems.org.
- Removed dependency on Jeweler.
- Fixed a bug where configuration errors could cause the `receive_messages` call to hang.

### 2016-09-06
- Released v5.0.3 to Rubygems.org.
- Overhauled Appsignal integration code.

### 2016-07-01
- Released v5.0.2 to Rubygems.org.
- Lowered log level of exception backtraces.

### 2016-06-22
- Released v5.0.1 to Rubygems.org.
- Improve Appsignal integration; only show parameters if the job actually supports those.
- Simplify CLI tests and add tests with mock workers.

### Current end of changelog. For earlier changes see the commit log on github.

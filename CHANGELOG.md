### 2017-05-26
- Released v5.0.6 to Rubygems.org.
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
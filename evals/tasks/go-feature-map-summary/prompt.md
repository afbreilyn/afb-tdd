Add a `Summary() string` method to `domain.Report` (in `domain/report.go`). It renders the title followed by all tags as `key=value` pairs in brackets, comma-separated — for example:

    Q1 Report [env=prod, team=payments]

A report with no tags renders just the title. The output must be stable across runs.

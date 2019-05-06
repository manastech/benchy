# Benchy

A tool to perform benchmarks.

Allows declaration of program to run and measurements to do (cpu time, user time, max resident set size, etc.) in a manifest `.yml` file.

The measurements will already compute average and standard deviation.

It supports client/server programs to run HTTP servers against tools like `ab`.

It supports runnings the program against multiple configurations.

## Installation

```sh
$ git clone https://github.com/manastech/benchy.git
$ cd benchy
$ shards build
```

Use `./bin/benchy` or copy it your somewhere in your PATH.

## Usage

Read the full [DOCS](./DOCS.md) or run one of the samples included in `./sample`

Ensure that `time` and `ab` are installed. `$ apt-get install time apache2-utils`

```sh
$ shards build
$ ./bin/benchy run --csv=output.csv ./sample/http.yml
```

## Contributing

1. Fork it (<https://github.com/manastech/benchy/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Brian J. Cardiff](https://github.com/bcardiff) - creator and maintainer

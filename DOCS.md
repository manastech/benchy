# Benchy

## Commands

Given a `manifest.yml` file there are three commands.

### run - Run all configurations

```sh
./benchy run -v --csv=output.csv --ndjson=output.ndjson --keep-logs manifest.yml
```

The `--csv` will store the measures in a CSV file.
The `--ndjson` will store the measures in a NDJSON file.
The `--keep-logs` will store in `.benchy_logs` the output of each execution.
The `-v,--verbose` will show verbose information of the running commands.

### run:\[index\] - Run single configuration

```sh
./benchy run:2 --keep-logs --repeat=1 manifest.yml
```

The `--repeat=1` will override the `repeat: N` of the manifest. Use full for checking just one run.

The `index` can be obtained by the `matrix` command. To run the last configuration `run:-1` can be used.

### matrix - Show the list of configurations

```sh
./benchy matrix manifest.yml
```

## Manifest

A `.yml` file will describe what is expected to measure.

The minimum manifest **MUST** include:

* a `name` for the experiment
* a list of what to `measure`
* the command to `run`

```yaml
name: sample
measure:
  - time
run: ./run
```

Commands are performed in the same directory as the manifest file.

To perform the experiment a couple of times `repeat` can be used.

```yaml
# ... stripped ...
run: ./run
repeat: 10
```

The built-in measures are `time`, `cpu_time`, `max_rss`.

```yaml
name: sample
measure:
  - time      # wall time in seconds
  - cpu_time  # cpu in seconds
  - max_rss   # max resident set size in bytes
run: ./run
```

The configurations are defined in `matrix`. Either declare the values for each command or define the whole list explicitly. Configurations affects the environment variables that are used to perform commands.

```yaml
run: ./run $FOO $BAR
matrix:
  env:
    FOO:
      - 10
      - 100
    BAR:
      - a
      - b
```

```yaml
matrix:
  include:
    -
      env:
        FOO: 10
        BAR: a
    -
      env:
        FOO: 10
        BAR: b
    -
      env:
        FOO: 100
        BAR: a
    -
      env:
        FOO: 100
        BAR: b
```

Around each run and around the whole suite run you can specify commands to be prepare the program or warm up some caches.

```yaml
# ... stripped ...
run: ./run
before: ./a
before_each: ./b
after_each: ./c
after: ./d
```

In case you want to measure an http server you will probably want to specify a `loader` script that will hit the server telling the
throughput or some other information. If a `loader` is specified in the manifest the `run` command will be killed after the former finishes.

A custom `measure` can be used to find the throughput in the loader's output. The `regex` either captures the whole value or a named group `<measure>` does it.

```yaml
name: sample
measure:
  - time
  - requests_per_second:
      regex: Requests per second:\s+(?<measure>\d+.\d+)\s+\[#/sec\] \(mean\)
run: ./http
loader: ./wait-for-it.sh 127.0.0.1:8080 -- ab -c $CONNECTIONS -n $REQUESTS http://127.0.0.1:8080/
matrix:
  env:
    REQUESTS:
      - 100
      - 1000
    CONNECTIONS:
      - 4
      - 40
```

The `context` section does not affect the commands but the serve for holding scripts that will describe the environment and context where the specs were, including them together with the measures. They can be used to extract library versions, host information or dates.

```yaml
name: sample
context:
  host: uname
  date: date +%Y-%m-%d
# ... stripped ...
```

### Complete example

```yaml
name: sample
context:
  host: uname
  date: date +%Y-%m-%d
measure:
  - time
  - cpu_time
  - max_rss
  - requests_per_second:
      regex: Requests per second:\s+(?<measure>\d+.\d+)\s+\[#/sec\] \(mean\)
run: ./run
loader: ./loader
repeat: 10
before: ./a
before_each: ./b
after_each: ./c
after: ./d
matrix:
  env:
    FOO:
      - 10
      - 100
    BAR:
      - a
      - b
  include:
    -
      env:
        FOO: 100
        BAR: z
```

require "./spec_helper"

private def it_parses(name, content, file = __FILE__, line = __LINE__)
  it "parses #{name}", file, line do
    Benchy::Manifest.from_yaml(content)
  end
end

describe Benchy::Manifest do
  it_parses "minimal", <<-YAML
  name: sample
  measure:
    - time
  run: ./run
  YAML

  it_parses "run with repeat and before/after", <<-YAML
  name: sample
  measure:
    - time
  run: ./run
  repeat: 8
  before: a
  before_each: b
  after_each: c
  after: d
  YAML

  it_parses "with loader", <<-YAML
  name: sample
  measure:
    - time
  run: ./http_server
  loader: ab -c 4 -n 100 http://127.0.0.1:8080/
  YAML

  it_parses "with matrix with strings", <<-YAML
  name: sample
  measure:
    - time
  run: ./run
  matrix:
    include:
      -
        env:
          times: "10"
          size: "10"
  YAML

  it_parses "with matrix with int", <<-YAML
  name: sample
  measure:
    - time
  run: ./run
  matrix:
    include:
      -
        env:
          times: 10
          size: 10
  YAML

  it_parses "custom meassure with regex", <<-YAML
  name: sample
  measure:
    - time
    - foo:
        regex: foo(<measure>\d+)bar
  run: ./run
  loader: ab
  YAML

  it_parses "custom meassure with group index and transform", <<-YAML
  name: sample
  measure:
    - time
    - foo:
        regex:
          pattern: hs(\d)f
          group: 1
          transform: tr '.' ''
  run: ./run
  loader: ab
  YAML

  it_parses "custom meassure with group name", <<-YAML
  name: sample
  measure:
    - time
    - foo:
        regex:
          pattern: /hs(<num>\d)f/
          group: num
  run: ./run
  YAML
end

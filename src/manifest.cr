require "yaml"
require "yaml_mapping"

module Benchy
  class Manifest
    class Matrix
      YAML.mapping(
        env: Hash(String, Array(String))?,
        include: Array(RunConfig)?
      )
    end

    class RunConfig
      YAML.mapping(
        env: Hash(String, String)
      )
    end

    class CustomMeasure
      YAML.mapping(
        regex: String | CustomRegexMeasure?,
        command: String?
      )
    end

    class CustomRegexMeasure
      YAML.mapping(
        pattern: String,
        group: Int64 | String?,
        transform: String?
      )
    end

    YAML.mapping(
      name: String,
      context: Hash(String, String)?,
      measure: Array(String | Hash(String, CustomMeasure)),
      run: String,
      repeat: Int32?,
      loader: String?,
      before: String?,
      before_each: String?,
      after_each: String?,
      after: String?,
      matrix: Matrix?
    )
  end
end

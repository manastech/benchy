require "csv"
require "option_parser"
require "./benchy"

cli_manifest_paths = nil
cli_csv_file = nil

OptionParser.parse! do |opts|
  opts.on("--csv=FILE", "Save results as csv") do |v|
    cli_csv_file = v
  end

  opts.unknown_args do |before_dash, after_dash|
    cli_manifest_paths = before_dash.map { |f| Path.new(f) }
  end
end

if manifest_paths = cli_manifest_paths
  manifest_paths.each do |manifest_path|
    manifest = Benchy::Manifest.from_yaml(File.read(manifest_path))
    project = Benchy::Project.new(manifest, manifest_path.parent)
    results = project.run

    if csv_file = cli_csv_file
      File.open(csv_file, mode: "w") do |io|
        context_keys = project.context.keys
        configuration_keys = project.configuration_keys
        measures_keys = project.measure_keys
        prefix = ->(p : String, keys : Array(String)) {
          keys.map { |k| "#{p}#{k}" }
        }
        CSV.build(io) do |csv|
          csv.row(["name"].concat(
            prefix.call("ctx.", context_keys))
            .concat(prefix.call("cnf.", configuration_keys))
            .concat(measures_keys.flat_map { |m| ["#{m}.avg", "#{m}.std"] })
            .concat(["succeeded", "errored"]))
          results.each do |r|
            csv.row([project.name].concat(
              context_keys.map { |k| project.context[k] })
              .concat(configuration_keys.map { |k| r.configuration[:env][k] })
              .concat(measures_keys.flat_map { |k| m = r.measures[k]; [m[:avg].to_s, m[:std].to_s] })
              .concat([r.succeeded.to_s, r.errored.to_s]))
          end
        end
      end
    end

    break # only perform one manifest for now
  end
end

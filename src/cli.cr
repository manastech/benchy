require "csv"
require "json"
require "option_parser"
require "./benchy"

def init_projects(manifest_paths)
  manifest_paths.map do |manifest_path|
    manifest = Benchy::Manifest.from_yaml(File.read(manifest_path))

    Benchy::Project.new(manifest, manifest_path.parent)
  end
end

def show_config(config)
  config[:env].each do |k, v|
    print k
    print "="
    print v
    print " "
  end
  puts
end

case ARGV.first?
when "run"
  cli_manifest_paths = nil
  cli_csv_file = nil
  cli_ndjson_file = nil
  cli_keep_logs = false

  OptionParser.parse(ARGV[1..]) do |opts|
    opts.on("--csv=FILE", "Save results as csv") do |v|
      cli_csv_file = v
    end

    opts.on("--ndjson=FILE", "Save results as ndjson") do |v|
      cli_ndjson_file = v
    end

    opts.on("--keep-logs", "Save run and loader logs") do |v|
      cli_keep_logs = v
    end

    opts.unknown_args do |before_dash, after_dash|
      cli_manifest_paths = before_dash.map { |f| Path.new(f) }
    end
  end

  if manifest_paths = cli_manifest_paths
    init_projects(manifest_paths).each do |project|
      results = project.run(
        run_logger: cli_keep_logs ? OutputRecorder.new(Path.new(Dir.current)) : nil
      )

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

      if ndjson_file = cli_ndjson_file
        File.open(ndjson_file, mode: "w") do |io|
          context_keys = project.context.keys
          configuration_keys = project.configuration_keys
          measures_keys = project.measure_keys

          results.each do |r|
            JSON.build(io) do |json|
              json.object do
                json.field "name", project.name
                json.field "context" do
                  json.object do
                    context_keys.each do |k|
                      json.field k, project.context[k]
                    end
                  end
                end
                json.field "configuration" do
                  json.object do
                    configuration_keys.each do |k|
                      json.field k, r.configuration[:env][k]
                    end
                  end
                end
                json.field "measures" do
                  json.object do
                    measures_keys.each do |k|
                      json.field k do
                        json.object do
                          m = r.measures[k]
                          json.field "avg", m[:avg]
                          json.field "std", m[:std]
                        end
                      end
                    end
                  end
                end
                json.field "succeeded", r.succeeded
                json.field "errored", r.errored
              end
            end
            io.puts
          end
        end
      end

      break # only perform one manifest for now
    end
  else
    # missing manifest .yml
  end
when /run:(-?\d+)/
  cli_manifest_paths = nil
  cli_keep_logs = false
  cli_repeat = nil

  OptionParser.parse(ARGV[1..]) do |opts|
    opts.on("--keep-logs", "Save run and loader logs") do |v|
      cli_keep_logs = v
    end

    opts.on("--repeat=N", "Override number of repeats") do |n|
      cli_repeat = n.to_i
    end

    opts.unknown_args do |before_dash, after_dash|
      cli_manifest_paths = before_dash.map { |f| Path.new(f) }
    end
  end

  config_selector = $1
  if manifest_paths = cli_manifest_paths
    init_projects(manifest_paths).each do |project|
      results = project.run(
        run_logger: cli_keep_logs ? OutputRecorder.new(Path.new(Dir.current)) : nil,
        config_selector: config_selector,
        repeat: cli_repeat
      )

      result = results.first

      show_config(result.configuration)
      puts "succeeded: #{result.succeeded}"
      puts "errored: #{result.errored}"
      result.measures.each do |k, m|
        print "#{k}: #{m[:avg]}"
        print " (#{m[:std]})" unless m[:std].nan?
        puts
      end

      break # only perform one manifest for now
    end
  else
    # missing manifest .yml
  end
when "matrix"
  manifest_paths = ARGV[1..].map { |f| Path.new(f) }
  init_projects(manifest_paths).each do |project|
    puts "#{project.name}:"
    project.configurations.each_with_index do |config, index|
      print "%5d: " % [index]
      show_config(config)
    end
    puts
  end
else
  puts <<-USAGE
    ./benchy [command] [switches] [manifest.yml]

    Command:
        run         runs a .yml manifest file
        run:index   runs a .yml manifest file against one single matrix configuration
        matrix      shows all the matrix configuration
    USAGE
end

require "./manifest"
require "./instrument"
require "./output_recorder"

module Benchy
  VERSION = "0.1.0"

  class Project
    alias Configuration = NamedTuple(env: Hash(String, String))
    alias Sample = Float64
    alias Measure = {avg: Sample, std: Sample}

    record RunOnceResult, status : Process::Status, measures : Hash(String, Sample)?
    record RunResult, configuration : Configuration, succeeded : Int32, errored : Int32, measures : Hash(String, Measure)
    record RunResultBuilder, configuration : Configuration, succeeded : Int32, errored : Int32, measures : Hash(String, Array(Sample)) do
      def self.zero(configuration : Configuration, measures : Array(String))
        RunResultBuilder.new(
          configuration: configuration,
          succeeded: 0, errored: 0,
          measures: measures.reduce(Hash(String, Array(Sample)).new) { |h, m| h[m] = Array(Sample).new; h }
        )
      end

      def add(r : RunOnceResult)
        @succeeded += r.status.success? ? 1 : 0
        @errored += r.status.success? ? 0 : 1
        if m = r.measures
          @measures.each do |key, value|
            value << m[key]
          end
        end
      end

      def build
        RunResult.new(configuration: configuration,
          succeeded: succeeded, errored: errored,
          measures: measures.transform_values { |s| RunResultBuilder.to_measure(s) })
      end

      def self.to_measure(samples : Array(Sample))
        avg = samples.sum / samples.size
        {avg: avg,
         std: Math.sqrt(samples.reduce(0f64) { |r, s| r + (s - avg) ** 2.0 } / (samples.size - 1.0))}
      end
    end

    alias ExtractSampleProc = Proc(String, Sample)

    getter name : String
    getter base_dir : Path
    getter context : Hash(String, String)
    getter configurations : Array(Configuration)
    getter main : String
    getter repeat : Int32
    getter loader : String?

    def initialize(manifest : Manifest, base_dir : Path)
      @base_dir = base_dir
      @name = manifest.name
      @context = Hash(String, String).new
      if manifest_context = manifest.context
        manifest_context.each do |key, cmd|
          @context[key] = get_output(cmd)
        end
      end

      @before = manifest.before
      @before_each = manifest.before_each
      @after_each = manifest.after_each
      @after = manifest.after

      @main = manifest.run
      @repeat = manifest.repeat || 1
      @loader = manifest.loader
      @configurations = Project.build_configurations(manifest)

      @measure_samplers = Project.build_samplers(manifest)

      has_bin_time = Process.run("which", {"/usr/bin/time"}, output: Process::Redirect::Close).success?
      raise "Missing /usr/bin/time" unless has_bin_time
    end

    def run(run_logger, *, config_selector = nil, repeat = nil) : Array(RunResult)
      res = Array(RunResult).new
      exec_before

      runnable_configurations(config_selector).each do |(configuration, config_index)|
        builder = RunResultBuilder.zero(configuration, measure_keys)
        (repeat || self.repeat).times do |run_index|
          builder.add(run_once(configuration, run_logger, config_index, run_index))
        end

        res << builder.build
      end

      exec_after

      res
    end

    def run_once(configuration : Configuration, run_logger, config_index, run_index) : RunOnceResult
      exec_before_each

      main_pid_file = File.tempname("main", ".pid")
      save_pid_and_wait = @loader ? " & echo $! > #{main_pid_file} & wait" : ""
      instrumented_main = "#{Benchy::BIN_TIME} /bin/sh -c '#{main}#{save_pid_and_wait}'"

      main_process = Process.new(command: instrumented_main,
        env: configuration[:env],
        shell: true,
        output: Process::Redirect::Pipe,
        error: Process::Redirect::Pipe,
        chdir: base_dir.to_s)

      loader_output = loader_error = ""
      loader_status = nil

      if loader = @loader
        loader_process = Process.new(command: loader,
          env: configuration[:env],
          shell: true,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Pipe,
          chdir: base_dir.to_s)

        loader_output = loader_process.output.gets_to_end
        loader_error = loader_process.error.gets_to_end
        loader_status = loader_process.wait

        `kill -9 #{File.read(main_pid_file)}`
        File.delete main_pid_file
        # TODO if the main errored alread (eg: busy port)
        #      the kill -9 will fail. Need to catch exception
      end

      main_output = main_process.output.gets_to_end
      main_error = main_process.error.gets_to_end
      main_status = main_process.wait

      run_status = main_status
      run_status = loader_status if loader_status && !loader_status.success?

      measures = extract_measures(main_output + main_error + loader_output + loader_error) if run_status.success?

      if run_logger
        run_logger.log(name: name, config_index: config_index, run_index: run_index,
          config: configuration, run_status: run_status,
          main_status: main_status, main_output: main_output, main_error: main_error,
          loader_status: loader_status, loader_output: loader_output, loader_error: loader_error,
          measures: measures)
      end

      RunOnceResult.new(
        status: run_status,
        measures: measures
      )
    ensure
      exec_after_each
    end

    {% for cmd in %i(before before_each after_each after) %}
      getter {{cmd.id}} : String?

      def exec_{{cmd.id}}
        if cmd = {{cmd.id}}
          exec cmd
        end
      end
    {% end %}

    private def get_output(cmd : String) : String
      exec(cmd).chomp
    end

    private def exec(cmd : String) : String
      Dir.cd base_dir.to_s do
        `#{cmd}`
      end
    end

    def runnable_configurations(config_selector = nil)
      if (index = config_selector.try(&.to_i?))
        index = index % configurations.size
        return [{configurations[index], index}]
      else
        configurations.map_with_index do |c, index|
          {c, index}
        end
      end
    end

    def measure_keys : Array(String)
      @measure_samplers.keys
    end

    def configuration_keys : Array(String)
      configurations.first[:env].keys
    end

    def extract_measures(main_output)
      @measure_samplers.transform_values do |proc|
        proc.call(main_output)
      end
    end

    def self.build_configurations(manifest)
      # no matrix means a single empty config
      result = [] of Configuration

      if (matrix_env = manifest.matrix.try(&.env)) &&
         !matrix_env.empty?
        # empty configuration to start duplicating them
        result << {env: Hash(String, String).new}

        matrix_env.each do |key, values|
          result = result.flat_map do |r|
            values.map do |v|
              r.clone.tap do |r|
                r[:env][key] = v
              end
            end
          end
        end
      end

      if (matrix_include = manifest.matrix.try(&.include)) &&
         !matrix_include.empty?
        matrix_include.each do |run_config|
          result << {env: run_config.env}
        end
      end

      result << {env: Hash(String, String).new} if result.empty?
      result
    end

    def self.build_samplers(manifest) : Hash(String, ExtractSampleProc)
      res = Hash(String, ExtractSampleProc).new

      manifest.measure.each do |mesure_config|
        case mesure_config
        when "max_rss"
          res["max_rss"] = MAX_RSS_PROC
        when "time"
          res["time"] = TIME_PROC
        when "cpu_time"
          res["cpu_time"] = CPU_TIME_PROC
        when Hash
          mesure_config.each do |key, config|
            proc = case config
                   when Manifest::CustomMeasure
                     pattern = case c = config.regex
                               when String
                                 c
                               else
                                 raise "Not Supported #{key} #{config}"
                               end

                     ->(main_output : String) {
                       md = main_output.match(Regex.new(pattern, :multiline))
                       raise "Missing #{key} measure" unless md
                       md["measure"]?.try(&.to_f64) || md[0].to_f64
                     }
                   end

            if proc
              res[key] = proc
            else
              raise "Not Supported #{key} #{config}"
            end
          end
        else
          raise "Not Supported #{mesure_config}"
        end
      end

      res
    end
  end
end

require "./manifest"
require "./instrument"

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

    def run : Array(RunResult)
      res = Array(RunResult).new
      exec_before

      runnable_configurations.each do |configuration|
        builder = RunResultBuilder.zero(configuration, measure_keys)
        repeat.times do
          builder.add(run_once(configuration))
        end

        res << builder.build
      end

      exec_after

      res
    end

    def run_once(configuration : Configuration) : RunOnceResult
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
      end

      main_output = main_process.output.gets_to_end
      main_error = main_process.error.gets_to_end
      main_status = main_process.wait

      run_status = main_status
      run_status = loader_status if loader_status && !loader_status.success?

      RunOnceResult.new(
        status: run_status,
        measures: run_status.success? ? extract_measures(main_output + main_error + loader_output + loader_error) : nil
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

    def runnable_configurations
      configurations
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
      if (matrix_include = manifest.matrix.try(&.include)) &&
         !matrix_include.empty?
        matrix_include.map do |run_config|
          {env: run_config.env.transform_values(&.to_s)}
        end
      else
        [{env: Hash(String, String).new}]
      end
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

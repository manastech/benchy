class OutputRecorder
  def initialize(@parent : Path)
  end

  def log(*, name, config_index, run_index, config, run_status,
          main_status, main_output, main_error,
          loader_status, loader_output, loader_error, measures)
    path = @parent / ".benchy_logs" / name / config_index.to_s
    Dir.mkdir_p(path.to_s)
    File.open(path / "#{run_index}.log", "w") do |f|
      sep = "=" * 40

      f.puts "name: #{name}"
      f.puts "config_index: #{config_index}"
      f.puts "config: #{config}"
      f.puts "run_status: #{run_status.exit_status}"
      f.puts "main_status: #{main_status.exit_status}"
      f.puts "loader_status: #{loader_status.exit_status}" if loader_status
      f.puts sep
      if measures
        measures.each do |k, v|
          f.puts "#{k}: #{v}"
        end
      end
      f.puts sep
      f.puts main_output
      f.puts sep
      f.puts main_error
      if loader_status
        f.puts sep
        f.puts loader_output
        f.puts sep
        f.puts loader_error
      end
    end
  end
end

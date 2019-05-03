module Benchy
  {% if flag?(:darwin) %}
    BIN_TIME = "/usr/bin/time -l"
    MAX_RSS_PROC = ->(output : String) {
      md = output.match /(\d+)\s+maximum resident set size/m
      raise "Missing max_rss measure" unless md
      # Kb to bytes
      (md[1].to_i64 * 1024).to_f64
    }

    TIME_REGEX = /(?<real>(\d+).(\d+))\sreal\s+(?<user>(\d+).(\d+))\suser\s+(?<sys>(\d+).(\d+))\ssys/m
    TIME_PROC = ->(output : String) {
      md = output.match TIME_REGEX
      raise "Missing time measure" unless md
      md["real"].to_f64
    }
    CPU_TIME_PROC = ->(output : String) {
      # TODO linux support
      md = output.match TIME_REGEX
      raise "Missing time measure" unless md
      md["user"].to_f64 + md["sys"].to_f64
    }
  {% else %}
    BIN_TIME = "/usr/bin/time -v"
    MAX_RSS_PROC = ->(output : String) {
      md = output.match /Maximum resident set size \(kbytes\):\s+(\d+)/m
      raise "Missing max_rss measure" unless md
      # Kb to bytes
      (md[1].to_i64 * 1024).to_f64
    }
    TIME_PROC = ->(output : String) {
      md = output.match /Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s+((?<h>\d+):)?(?<m>\d+):(?<s>\d\d(.\d*)?)/m
      raise "Missing time measure" unless md
      (md["h"]? || 0).to_f64 * 3600.0 + md["m"].to_f64 * 60.0 + md["s"].to_f64
    }
    CPU_TIME_PROC = ->(output : String) {
      md_user = output.match /User time \(seconds\):\s+(\d+.\d+)/m
      md_sys = output.match /System time \(seconds\):\s+(\d+.\d+)/m
      raise "Missing time measure" unless md_user && md_sys
      md_user[1].to_f64 + md_sys[1].to_f64
    }
  {% end %}
end

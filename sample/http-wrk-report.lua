-- See https://github.com/wg/wrk/blob/master/scripts/report.lua

done = function(summary, latency, requests)
  io.write(string.format("Requests per second: %f [#/sec] (mean)\n", requests.mean))
end

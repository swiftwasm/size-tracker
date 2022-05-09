require "json"
require "date"

data_file = ARGV[0] || "data.json"

data = if File.exist?(data_file)
         JSON.parse(File.read(data_file))
       else
         {"artifacts" => []}
       end
since_date = if ARGV.length >= 2
               d = DateTime.parse(ARGV[1])
               if data["updated_at"] && d < DateTime.parse(data["updated_at"])
                 raise "#{d} is older than #{data["updated_at"]}, when the data is updated at"
               end
               d
             else
               if data["updated_at"]
                 DateTime.parse(data["updated_at"])
               end
             end

latest_run = nil
page = 1

loop do
  puts "Fetching page #{page}..."
  result = %x(gh api 'repos/swiftwasm/swift/actions/runs?branch=swiftwasm&status=success&page=#{page}&per_page=100')
  result = JSON.parse(result)
  runs = result["workflow_runs"]
  if latest_run.nil? && !runs.empty?
    latest_run = runs[0]
    data["updated_at"] = latest_run["created_at"]
  end

  break if runs.empty?

  artifacts = runs.filter_map do |run|
    next nil if DateTime.parse(run["created_at"]) <= since_date
    puts "Fetching artifact of #{run["id"]}..."
    artifacts_result = %x(gh api '#{run["artifacts_url"]}')
    artifacts_result = JSON.parse(artifacts_result)
    artifact = artifacts_result["artifacts"].find{ _1["name"] == "ubuntu20.04_x86_64-hello.wasm" }
    next nil unless artifact
    {
      "run_id": run["id"],
      "created_at": run["created_at"],
      "commit": run["head_sha"],
      "size_in_bytes": artifact["size_in_bytes"]
    }
  end

  data["artifacts"].prepend(*artifacts)
  File.write(data_file, JSON.pretty_generate(data))
  page += 1

  oldest_date = DateTime.parse(runs.last["created_at"])
  if since_date && oldest_date < since_date
    puts "No new artifact found in page #{page}"
    break
  end
end

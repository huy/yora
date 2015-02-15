require 'open3'

module GitUtil
  def git(cmd)
    $stderr.puts "-- cmd = #{cmd}"

    o, e, s = Open3.capture3(cmd)

    $stderr.puts "-- stderr = #{e}"
    $stderr.puts "-- stdout = #{o}"

    unless s.success?
      $stderr.puts '-- crash due to git command error'
      exit(1)
    end
  end

  module_function :git
end

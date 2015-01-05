require 'fileutils'
require_relative 'message'

module Yora
  class FileStore
    include Message

    attr_accessor :current_term, :voted_for, :cluster

    def initialize(node_id, node_address)
      @log_path = "data/#{node_id}/current_log.txt"
      @metadata_path = "data/#{node_id}/current_data.txt"

      @log_entries = [LogEntry.new(0, nil)]

      [@log_path, @metadata_path].map { |p| File.dirname(p) }.each do |dir|
        FileUtils.mkdir_p(dir)
      end

      @cluster = { node_id => node_address }
      if File.exist?(@log_path)
        File.open(@log_path, 'r').each_line do |line|
          entry = deserialize(line, false)

          @cluster = entry.cluster if entry.config?

          @log_entries << entry
        end
      end

      @current_term = 0
      @voted_for = nil
      if File.exist?(@metadata_path)
        metadata = deserialize(File.read(@metadata_path))

        @current_term = metadata[:current_term]
        @voted_for = metadata[:voted_for]
      end
    end

    def concat(entries)
      @log_entries.concat(entries)
    end

    def [](index)
      @log_entries[index]
    end

    def slice(range)
      @log_entries.slice(range)
    end

    def size
      @log_entries.size
    end

    def truncate(index)
      @log_entries[(index + 1)..-1] = []
    end

    def last
      @log_entries.last
    end

    def save
      File.open(@log_path, 'w') do |f|
        slice(1..-1).each do |entry|
          f.puts(serialize(entry))
        end
      end
      File.open(@metadata_path, 'w') do |f|
        f.puts(serialize(current_term: @current_term, voted_for: @voted_for))
      end
    end
  end
end

require 'json'

module Yora
  class LogEntry
    attr_reader :term, :command, :client

    def initialize(term, command = nil, client = nil)
      @term = term
      @command = command
      @client = client
    end

    def to_json(*opts)
      {
        'json_class'   => self.class.name,
        'data' => { 'term' => @term,
                    'command' => @command,
                    'client' => client
                  }
      }.to_json(*opts)
    end

    def self.json_create(json)
      new(json['data']['term'], json['data']['command'], json['data']['client'])
    end

    def config?
      false
    end

    def noop?
      @command.nil?
    end
  end

  class ConfigLogEntry
    attr_reader :term, :cluster

    def initialize(term, cluster)
      @term = term
      @cluster = cluster
    end

    def to_json(*opts)
      {
        'json_class'   => self.class.name,
        'data' => { 'term' => @term,
                    'cluster' => @cluster
                  }
      }.to_json(*opts)
    end

    def self.json_create(json)
      new(json['data']['term'], json['data']['cluster'])
    end

    def config?
      true
    end

    def noop?
      false
    end
  end
end

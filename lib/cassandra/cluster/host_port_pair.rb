module Cassandra
  module Cluster
    class HostPortPair < SimpleDelegator
      attr_accessor :port
    end
  end
end

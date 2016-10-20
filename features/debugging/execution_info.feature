Feature: Execution information

  Every result contains [useful execution information](/api/execution/info/).

  Background:
    Given a running cassandra cluster with schema:
      """cql
      CREATE KEYSPACE simplex WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
      CREATE TABLE simplex.songs (
        id uuid PRIMARY KEY,
        title text,
        album text,
        artist text,
        tags set<text>,
        data blob
      );
      INSERT INTO simplex.songs (id, title, album, artist, tags)
      VALUES (
         756716f7-2e54-4715-9f00-91dcbea6cf50,
         'La Petite Tonkinoise',
         'Bye Bye Blackbird',
         'Joséphine Baker',
         {'jazz', '2013'})
      ;
      INSERT INTO simplex.songs (id, title, album, artist, tags)
      VALUES (
         f6071e72-48ec-4fcb-bf3e-379c8a696488,
         'Die Mösch',
         'In Gold',
         'Willi Ostermann',
         {'kölsch', '1996', 'birds'}
      );
      INSERT INTO simplex.songs (id, title, album, artist, tags)
      VALUES (
         fbdf82ed-0063-4796-9c7c-a3d4f47b4b25,
         'Memo From Turner',
         'Performance',
         'Mick Jager',
         {'soundtrack', '1991'}
      );
      """

  Scenario: execution information is accessible from execution result
    Given the following example:
      """ruby
      require 'cassandra'

      cluster   = Cassandra.cluster
      session   = cluster.connect("simplex")
      execution = session.execute("SELECT * FROM songs", consistency: :one).execution_info

      puts "coordinator: #{execution.hosts.last.ip}"
      puts "keyspace: #{execution.keyspace}"
      puts "cql: #{execution.statement.cql}"
      puts "requested consistency: #{execution.options.consistency}"
      puts "actual consistency: #{execution.consistency}"
      puts "number of retries: #{execution.retries}"
      """
    When it is executed
    Then its output should match:
      """
      coordinator: 127\.0\.0\.(1|2|3)
      """
    And its output should contain:
      """
      keyspace: simplex
      cql: SELECT * FROM songs
      requested consistency: one
      actual consistency: one
      number of retries: 0
      """

  @cassandra-version-specific @cassandra-version-2.2
  Scenario: execution information includes warnings
    Given the following example:
      """ruby
      require 'cassandra'

      cluster   = Cassandra.cluster
      session   = cluster.connect("simplex")

      insert = session.prepare('INSERT INTO simplex.songs ' +
                                               '(id, title, album, artist, tags) values ' +
                                               '(?, ?, ?, ?, ?)')

      args0 = [Cassandra::Uuid.new('f6071e72-48ec-4fcb-bf3e-379c8d696488'), 'a' * 5 * 1025, 'a1', 'a1', Set.new(['t1'])]
      args1 = [Cassandra::Uuid.new('f6071e72-48ec-4fcb-bf3e-379c8d696498'), 'a' * 5 * 1025, 'a1', 'a1', Set.new(['t1'])]
      batch = session.unlogged_batch do |b|
        b.add(insert, arguments: args0)
        b.add(insert, arguments: args1)
      end
      execution_info = session.execute(batch).execution_info

      puts "warnings: #{execution_info.warnings.first}"
      """
    When it is executed
    Then its output should match:
      """
      warnings: Batch.* for .* is of size .*, exceeding specified threshold of 5120
      """

  Scenario: execution information reflects retry decision
    Given a file named "retrying_at_a_given_consistency_policy.rb" with:
      """ruby
      class RetryingAtAGivenConsistencyPolicy
        include Cassandra::Retry::Policy

        def initialize(consistency_to_use)
          @consistency_to_use = consistency_to_use
        end

        def read_timeout(statement, consistency_level, required_responses,
                         received_responses, data_retrieved, retries)
          try_again(@consistency_to_use)
        end

        def write_timeout(statement, consistency_level, write_type,
                          acks_required, acks_received, retries)
          try_again(@consistency_to_use)
        end

        def unavailable(statement, consistency_level, replicas_required,
                        replicas_alive, retries)
          try_again(@consistency_to_use)
        end
      end
      """
    And the following example:
      """ruby
      require 'cassandra'
      require 'retrying_at_a_given_consistency_policy'

      cluster   = Cassandra.cluster(retry_policy: RetryingAtAGivenConsistencyPolicy.new(:one))
      session   = cluster.connect("simplex")
      execution = session.execute("SELECT * FROM songs", consistency: :all).execution_info

      puts "requested consistency: #{execution.options.consistency}"
      puts "actual consistency: #{execution.consistency}"
      puts "number of retries: #{execution.retries}"
      """
    When node 3 stops
    And it is executed
    Then its output should contain:
      """
      requested consistency: all
      actual consistency: one
      number of retries: 1
      """

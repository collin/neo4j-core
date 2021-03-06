module Neo4j
  class Session

    @@current_session = nil
    @@all_sessions = {}
    @@factories = {}

    # @abstract
    def close
      self.class.unregister(self)
    end

    # Only for embedded database
    # @abstract
    def start
      raise "not impl."
    end

    # Only for embedded database
    # @abstract
    def shutdown
      raise "not impl."
    end

    # Only for embedded database
    # @abstract
    def running
      raise "not impl."
    end

    # @return [:embedded_db | :server_db]
    def db_type
      raise "not impl."
    end

    def auto_commit?
      true # TODO
    end

    # @abstract
    def begin_tx
      raise "not impl."
    end

    class CypherError < StandardError
      attr_reader :error_msg, :error_status, :error_code
      def initialize(error_msg, error_code, error_status)
        super(error_msg)
        @error_msg = error_msg
        @error_status = error_status
      end
    end

    # Returns a Query object.  See Neo4j::Core::Query for more details, but basic usage looks like:
    #
    # @example
    #   session.query.match("(c:Car)<-[:OWNS]-(p:Person)").where(c: {vin: '234UAEB3425B'}).return(:p).first[:p]
    #
    # @see http://docs.neo4j.org/chunked/milestone/cypher-query-lang.html The Cypher Query Language Documentation
    #
    def query(options = {})
      raise 'not implemented, abstract'
    end

    # Same as #query but does not accept an DSL and returns the raw result from the database.
    # Notice, it might return different values depending on which database is used, embedded or server.
    # @abstract
    def _query(*params)
      raise 'not implemented'
    end

    class << self
      # Creates a new session to Neo4j
      # @see also Neo4j::Server::CypherSession#open for :server_db params
      # @param db_type the type of database, e.g. :embedded_db, or :server_db
      def open(db_type=:server_db, *params)
        register(create_session(db_type, params))
      end

      def open_named(db_type, name, default = nil, *params)
        raise "Multiple sessions is currently only supported for Neo4j Server connections." unless db_type == :server_db
        register(create_session(db_type, params), name, default)
      end

      def create_session(db_type, params = {})
        unless (@@factories[db_type])
          raise "Can't connect to database '#{db_type}', available #{@@factories.keys.join(',')}"
        end
        @@factories[db_type].call(*params)
      end

      def current
        @@current_session
      end

      def current!
        raise "No session, please create a session first with Neo4j::Session.open(:server_db) or :embedded_db" unless current
        current
      end

      # @see Neo4j::Session#query
      def query(options = {})
        current!.query(options)
      end

      def named(name)
        @@all_sessions[name] || raise("No session named #{name}.")
      end

      def set_current(session)
        @@current_session = session
      end

      # Registers a callback which will be called immediately if session is already available,
      # or called when it later becomes available.
      def on_session_available(&callback)
        if (Neo4j::Session.current)
          callback.call(Neo4j::Session.current)
        end
        add_listener do |event, data|
          callback.call(data) if event == :session_available
        end
      end

      def add_listener(&listener)
        self._listeners << listener
      end

      def _listeners
        @@listeners ||= []
        @@listeners
      end

      def _notify_listeners(event, data)
        _listeners.each {|li| li.call(event, data)}
      end

      def register(session, name = nil, default = nil)
        if default == true
          set_current(session)
        elsif default.nil?
          set_current(session) unless @@current_session
        end
        @@all_sessions[name] = session if name
        @@current_session
      end

      def unregister(session)
        @@current_session = nil if @@current_session == session
      end

      def inspect
         "Neo4j::Session available: #{@@factories && @@factories.keys}"
      end

      def register_db(db, &session_factory)
        puts "replace factory for #{db}" if @@factories[db]
        @@factories[db] = session_factory
      end
    end
  end
end

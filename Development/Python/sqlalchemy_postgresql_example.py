# Extended version with more features
# https://www.psycopg.org/docs/connection.html (default behavior requires manual commit
# https://docs.sqlalchemy.org/en/20/dialects/postgresql.html#psycopg2-isolation-level
# https://docs.sqlalchemy.org/en/20/core/connections.html#setting-isolation-level-or-dbapi-autocommit-for-an-engine
from sqlalchemy import create_engine, text
from sqlalchemy.pool import QueuePool
from sqlalchemy.exc import SQLAlchemyError, DBAPIError
import concurrent.futures
import time
import logging
from datetime import datetime
import os
import signal
import sys
from contextlib import contextmanager

class DatabaseConnectionManager:
    def __init__(self, connection_params=None):
        # Default connection parameters
        self.params = {
            'host': os.getenv("PGHOST", "localhost"),
            'port': os.getenv("PGPORT", "5432"),
            'user': os.getenv("PGUSER", "hr"),
            'password': os.getenv("PGPASSWORD", "hr"),
            'database': os.getenv("PGDATABASE", "mytest"),
            'pool_size': 10,
            'max_overflow': 10,
            'pool_timeout': 30,
            'pool_recycle': 60,  # Default is 1800, change to 1 minute to avoid better load balancing connections in Aurora
            'pool_pre_ping': True,
            'connect_timeout': 10,
            'application_name': 'aurora_connection_manager'
        }
        
        # Update with provided parameters
        if connection_params:
            self.params.update(connection_params)
        
        # Create engine
        self.engine = self._create_engine()
        
        # Setup logging
        self._setup_logging()
        
        # Flag for graceful shutdown
        self.running = True
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _create_engine(self):
        """Create SQLAlchemy engine with connection pool"""
        url = (f"postgresql://{self.params['user']}:{self.params['password']}"
               f"@{self.params['host']}:{self.params['port']}"
               f"/{self.params['database']}")
        
        return create_engine(
            url,
            poolclass=QueuePool,
            pool_size=self.params['pool_size'],
            max_overflow=self.params['max_overflow'],
            pool_timeout=self.params['pool_timeout'],
            pool_recycle=self.params['pool_recycle'],
            pool_pre_ping=self.params['pool_pre_ping'],
            connect_args={
                'connect_timeout': self.params['connect_timeout'],
                'application_name': self.params['application_name']
            },
	   execution_options={"isolation_level": "AUTOCOMMIT"}
        )

    def _setup_logging(self):
        """Configure logging"""
        self.logger = logging.getLogger(__name__)
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(threadName)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)
            self.logger.setLevel(logging.INFO)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}. Starting graceful shutdown...")
        self.running = False

    @contextmanager
    def get_connection(self):
        """Connection context manager"""
        connection = self.engine.connect()
        # Set session parameters
        connection.execute(text("SET log_min_duration_statement = 0"))
        try:
            yield connection
        finally:
            connection.close()

    def query_database(self, connection_id):
        """Execute queries on a dedicated connection"""
        while self.running:
            try:
                with self.get_connection() as conn:
                    # Execute query
                    result = conn.execute(text("""
                        SELECT 
                            inet_server_addr() AS server_addr,
                            current_setting('listen_addresses') AS listen_addr,
                            inet_server_port() AS port,
                            current_timestamp AS query_time
                    """))
                    row = result.fetchone()
                    
                    if row:
                        # Convert SQLAlchemy Row to dictionary using _mapping
                        row_dict = row._mapping
                        self.logger.info(f"Connection {connection_id}: {row_dict}")
                    else:
                        self.logger.warning(f"Connection {connection_id}: No results returned")
                        
                    
                    # Wait for next iteration
                    time.sleep(1)
                    
            except SQLAlchemyError as e:
                self.logger.error(
                    f"Database error in connection {connection_id}: {e}"
                )
                time.sleep(1)
            except Exception as e:
                self.logger.error(
                    f"Unexpected error in connection {connection_id}: {e}"
                )
                time.sleep(1)

    def monitor_pool(self):
        """Monitor connection pool status"""
        while self.running:
            try:
                status = {
                    'pool_size': self.engine.pool.size(),
                    'checked_out': self.engine.pool.checkedout(),
                    'overflow': self.engine.pool.overflow(),
                    'checkedin': self.engine.pool.checkedin(),
                }
                self.logger.info(f"Pool Status: {status}")
                time.sleep(5)
            except Exception as e:
                self.logger.error(f"Pool monitoring error: {e}")
                time.sleep(1)

    def run(self, num_connections=9):
        """Run the database connections"""
        self.logger.info(f"Starting {num_connections} database connections...")
        
        try:
            with concurrent.futures.ThreadPoolExecutor(
                max_workers=num_connections + 1
            ) as executor:
                # Start connection threads
                connection_futures = [
                    executor.submit(self.query_database, i)
                    for i in range(num_connections)
                ]
                
                # Start pool monitoring
                monitor_future = executor.submit(self.monitor_pool)
                
                # Wait for completion or error
                concurrent.futures.wait(
                    connection_futures + [monitor_future],
                    return_when=concurrent.futures.FIRST_EXCEPTION
                )
                
        except Exception as e:
            self.logger.error(f"Error in main execution: {e}")
        finally:
            self.running = False
            self.engine.dispose()
            self.logger.info("Database connections closed")

if __name__ == "__main__":
    # Create and run connection manager
    manager = DatabaseConnectionManager()
    manager.run(9)

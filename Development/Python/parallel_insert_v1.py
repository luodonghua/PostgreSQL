import multiprocessing.process
from multiprocessing import Pool
import psycopg2
import logging
import time


# Configure the logger
logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=logging.INFO)

# Database connection details
DB_HOST = "localhost"
DB_NAME = "mytest"
DB_USER = "hr"
DB_PASSWORD = "hr"

# Number of parallel processes
NUM_PROCESSES = 4

def insert_data(work_data):
    
    logging.info("Start to Process data range "  + str(work_data))
    start_time = time.time()  # Get the start time

    conn = psycopg2.connect(
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )
    cur = conn.cursor()

    insert_query = '''INSERT INTO t_txn(id, c1, c2, update_ts) 
                    select i, rpad(i::text,1000,'x'),rpad(i::text,1000,'y'), 
                    to_timestamp('2024-01-01 00:00','YYYY-MM-DD HH24:MI')+(interval '0.01 sec')*i 
                    from generate_series(%s,%s) i''';
    
    cur.execute(insert_query, (work_data[0], work_data[1]))
    conn.commit()
    cur.close()
    conn.close()

    end_time = time.time()  # Get the end time
    execution_time = end_time - start_time

    logging.info("End to Process data range "  + str(work_data) + f" in {execution_time:.6f} seconds")


def pool_handler(work):
    p = Pool(NUM_PROCESSES)
    p.map(insert_data, [work_data for work_data in work])
    logging.info("Parallel inserts completed successfully.")

if __name__ == '__main__':
    
    range_start_id = 1
    range_end_id = 10000
    range_partition_size=100
    work = []
    for i in range(range_start_id, range_end_id, range_partition_size):
        work.append((i, i+range_partition_size-1))
    
    # Process the insert using multithread pool
    # print(work)
    pool_handler(work)


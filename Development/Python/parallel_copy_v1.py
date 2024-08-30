import psycopg2
import logging
import time
from multiprocessing import Lock, Process, Queue, current_process
import queue # imported for using queue.Empty exception
from datetime import datetime

# Configure the logger
logging.basicConfig(format='%(asctime)s - %(levelname)s - %(message)s', level=logging.INFO)

# Database connection details
DB_HOST = "localhost"
DB_NAME = "mytest"
DB_USER = "hr"
DB_PASSWORD = "hr"

# Number of parallel processes
number_of_processes = 4

# Data Range
range_start_timestamp = datetime.strptime("2024-01-01 00:00:00", '%Y-%m-%d %H:%M:%S')
range_end_timestamp = datetime.strptime("2024-01-01 02:47:00", '%Y-%m-%d %H:%M:%S')
range_partition_size_second = 60

def copy_data(work_data):
    
    logging.info("Start to Process data range "  + str(work_data))
    start_time = time.time()  # Get the start time

    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        with conn.cursor() as cur:
            # Set tuning parameters if needed
            # cur.execute('SET  synchronous_commit TO off')

            insert_query = '''INSERT INTO t_txn_new (id, c1, c2, update_ts) 
                              select id, c1, c2, update_ts 
                              from t_txn where update_ts >= %s and update_ts < %s''';
            
            cur.execute(insert_query, (work_data[0], work_data[1]))
            conn.commit()
            
        conn.close()
    except Exception as e:
        print(e)
    finally:
        conn.close()

    end_time = time.time()  # Get the end time
    execution_time = end_time - start_time

    logging.info("End to Process data range "  + str(work_data) + f" in {execution_time:.6f} seconds")


def do_job(tasks_to_accomplish, tasks_that_are_done):
    
    while True:

        try:
            '''
                try to get task from the queue. get_nowait() function will 
                raise queue.Empty exception if the queue is empty. 
                queue(False) function would do the same task also.
            '''

            # task = tasks_to_accomplish.get_nowait()
            task = tasks_to_accomplish.get(block=True, timeout=5)
        except queue.Empty:
            break;
        else:
            '''
                if no exception has been raised, add the task completion 
                message to task_that_are_done queue
            '''
            copy_data(task)
            # print(task)
            logging.info(str(task) + ' is done by ' + current_process().name)
            tasks_that_are_done.put(str(task) + ' is done by ' + current_process().name)
    return True


if __name__ == '__main__':
    tasks_to_accomplish = Queue()
    tasks_that_are_done = Queue()
    processes = []

    for i in range(int(range_start_timestamp.timestamp()), int(range_end_timestamp.timestamp()), range_partition_size_second):
      # Range has overlap, process it based on [start, end) definition
      tasks_to_accomplish.put((datetime.fromtimestamp(i), datetime.fromtimestamp(i+range_partition_size_second)))

    # creating processes
    for w in range(number_of_processes):
        p = Process(target=do_job, args=(tasks_to_accomplish, tasks_that_are_done))
        processes.append(p)
        p.start()

    # completing process
    for p in processes:
        p.join()

    # print the output
    #while not tasks_that_are_done.empty():
    #    logging.info(tasks_that_are_done.get())

    logging.info("Parallel copies completed successfully.")
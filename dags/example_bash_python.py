"""
Example Airflow DAG: Basic Bash and Python Operators
This DAG demonstrates simple task dependencies using BashOperator and PythonOperator
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator

# Default arguments for the DAG
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
dag = DAG(
    'example_bash_python',
    default_args=default_args,
    description='A simple DAG with Bash and Python operators',
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['example', 'bash', 'python'],
)


def print_hello():
    """Simple Python function to print hello message"""
    print("Hello from Python!")
    print(f"Current time: {datetime.now()}")
    return "Python task completed successfully"


def process_data(**context):
    """Example Python function that processes data and uses XCom"""
    execution_date = context['execution_date']
    print(f"Processing data for execution date: {execution_date}")
    
    # Simulate data processing
    data = {
        'processed_items': 42,
        'status': 'success',
        'timestamp': str(datetime.now())
    }
    
    print(f"Data processed: {data}")
    return data


def print_results(**context):
    """Retrieve results from previous task using XCom"""
    ti = context['task_instance']
    data = ti.xcom_pull(task_ids='process_data')
    print(f"Retrieved data from previous task: {data}")
    print(f"Processed {data.get('processed_items', 0)} items")


# Task 1: Print date with Bash
task_print_date = BashOperator(
    task_id='print_date',
    bash_command='date',
    dag=dag,
)

# Task 2: Simple hello from Python
task_hello_python = PythonOperator(
    task_id='hello_python',
    python_callable=print_hello,
    dag=dag,
)

# Task 3: Process data
task_process_data = PythonOperator(
    task_id='process_data',
    python_callable=process_data,
    provide_context=True,
    dag=dag,
)

# Task 4: Print environment variables
task_print_env = BashOperator(
    task_id='print_env',
    bash_command='echo "Running in: $HOSTNAME" && echo "User: $USER" && echo "Path: $PATH"',
    dag=dag,
)

# Task 5: Print results from previous task
task_print_results = PythonOperator(
    task_id='print_results',
    python_callable=print_results,
    provide_context=True,
    dag=dag,
)

# Task 6: Final summary
task_summary = BashOperator(
    task_id='summary',
    bash_command='echo "DAG execution completed successfully!"',
    dag=dag,
)

# Define task dependencies
# Linear flow: print_date -> hello_python -> process_data -> print_env -> print_results -> summary
task_print_date >> task_hello_python >> task_process_data >> task_print_env >> task_print_results >> task_summary

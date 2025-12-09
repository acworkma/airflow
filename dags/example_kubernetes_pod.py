"""
Example Airflow DAG: Kubernetes Pod Operator
This DAG demonstrates using KubernetesPodOperator to run tasks in separate Kubernetes pods
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from kubernetes.client import models as k8s

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
    'example_kubernetes_pod',
    default_args=default_args,
    description='A DAG demonstrating KubernetesPodOperator',
    schedule_interval=None,  # Manual trigger only
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['example', 'kubernetes', 'pod'],
)

# Task 1: Run a simple Ubuntu container
task_ubuntu = KubernetesPodOperator(
    task_id='run_ubuntu_pod',
    name='ubuntu-pod',
    namespace='airflow',
    image='ubuntu:22.04',
    cmds=['bash', '-c'],
    arguments=['echo "Hello from Ubuntu pod!" && uname -a && date'],
    labels={'app': 'airflow', 'task': 'ubuntu'},
    get_logs=True,
    is_delete_operator_pod=True,
    dag=dag,
)

# Task 2: Run Python in a container
task_python = KubernetesPodOperator(
    task_id='run_python_pod',
    name='python-pod',
    namespace='airflow',
    image='python:3.11-slim',
    cmds=['python', '-c'],
    arguments=[
        'import sys; import platform; '
        'print(f"Python version: {sys.version}"); '
        'print(f"Platform: {platform.platform()}"); '
        'print("Task completed successfully!")'
    ],
    labels={'app': 'airflow', 'task': 'python'},
    get_logs=True,
    is_delete_operator_pod=True,
    dag=dag,
)

# Task 3: Run a data processing simulation
task_data_processing = KubernetesPodOperator(
    task_id='data_processing_pod',
    name='data-processing-pod',
    namespace='airflow',
    image='python:3.11-slim',
    cmds=['python', '-c'],
    arguments=[
        'import time; '
        'import random; '
        'print("Starting data processing..."); '
        'for i in range(5): '
        '    print(f"Processing batch {i+1}/5..."); '
        '    time.sleep(2); '
        'print("Data processing completed!"); '
        'print(f"Processed {random.randint(100, 1000)} records")'
    ],
    labels={'app': 'airflow', 'task': 'data-processing'},
    get_logs=True,
    is_delete_operator_pod=True,
    # Resource configuration
    container_resources=k8s.V1ResourceRequirements(
        requests={'memory': '128Mi', 'cpu': '100m'},
        limits={'memory': '256Mi', 'cpu': '200m'},
    ),
    dag=dag,
)

# Task 4: Run curl to test network connectivity
task_network_test = KubernetesPodOperator(
    task_id='network_test_pod',
    name='network-test-pod',
    namespace='airflow',
    image='curlimages/curl:latest',
    cmds=['sh', '-c'],
    arguments=[
        'echo "Testing network connectivity..." && '
        'curl -s https://api.github.com/repos/apache/airflow | head -20 && '
        'echo "Network test completed!"'
    ],
    labels={'app': 'airflow', 'task': 'network-test'},
    get_logs=True,
    is_delete_operator_pod=True,
    dag=dag,
)

# Define task dependencies
# Run ubuntu and python in parallel, then data processing, then network test
[task_ubuntu, task_python] >> task_data_processing >> task_network_test

import logging
import multiprocessing.synchronize
import os
import shutil
import threading

# Lambda has no /dev/shm — POSIX semaphores fail. Replace with threading equivalents.
multiprocessing.synchronize.Lock = lambda *a, **kw: threading.Lock()
multiprocessing.synchronize.RLock = lambda *a, **kw: threading.RLock()

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROJECT_DIR = os.environ.get("LAMBDA_TASK_ROOT", "/var/task")

os.environ["DBT_LOG_PATH"] = "/tmp/dbt_logs"
os.environ["DBT_TARGET_PATH"] = "/tmp/dbt_target"
os.environ["DBT_PACKAGES_INSTALL_PATH"] = "/tmp/dbt_packages"

# Import dbt AFTER the monkey-patch
from dbt.cli.main import dbtRunner

LAYER_ORDER = ["staging", "silver", "gold"]


def run_dbt(command, select=None):
    args = [command, "--project-dir", PROJECT_DIR, "--profiles-dir", PROJECT_DIR, "--threads", "1"]
    if select:
        args.extend(["--select", select])

    logger.info(f"Running: dbt {' '.join(args)}")

    runner = dbtRunner()
    result = runner.invoke(args)

    success = result.success
    output = str(result.result) if result.result else ""

    if result.exception:
        logger.error(f"dbt exception: {result.exception}")

    return {
        "success": success,
        "output": output[-3000:],
        "error": str(result.exception)[-1000:] if result.exception else "",
    }


def lambda_handler(event, context):
    command = event.get("command", "run")
    select = event.get("select")

    # dbt_packages installed at build time in /var/task — copy to writable /tmp on cold start
    src, dst = f"{PROJECT_DIR}/dbt_packages", "/tmp/dbt_packages"
    if os.path.exists(src) and not os.path.exists(dst):
        shutil.copytree(src, dst)

    # If a specific select is provided, run only that
    if select:
        result = run_dbt(command, select)
        if not result["success"]:
            raise Exception(f"dbt {command} --select {select} failed: {result['error']}")
        return {"statusCode": 200, "command": command, "layers": [result]}

    # or else run layers : staging → silver → gold
    results = []
    for layer in LAYER_ORDER:
        logger.info(f"--- Running layer: {layer} ---")
        result = run_dbt(command, layer)
        results.append({"layer": layer, **result})

        if not result["success"]:
            logger.error(f"Layer {layer} failed, stopping pipeline")
            return {"statusCode": 500, "command": command, "failed_at": layer, "layers": results}

    return {"statusCode": 200, "command": command, "layers": results}

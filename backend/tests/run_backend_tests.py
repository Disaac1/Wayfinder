#!/usr/bin/env python3
import os
import sys

if __name__ == "__main__":
    # Forward to tools/run_backend_tests.py
    tools_runner = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "tools", "run_backend_tests.py"))
    if os.path.isfile(tools_runner):
        import runpy
        sys.path.insert(0, os.path.dirname(tools_runner))
        runpy.run_path(tools_runner, run_name="__main__")
    else:
        print(f"Error: Could not locate tools/run_backend_tests.py at {tools_runner}")
        sys.exit(1)

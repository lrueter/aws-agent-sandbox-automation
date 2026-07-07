#!/usr/bin/env python3
"""Basic ForgeVM Python SDK usage.

Adapted from the upstream ForgeVM examples (MIT) —
https://github.com/DohaerisAI/forgevm/tree/main/examples/python — to read the
server URL and sandbox image from environment variables, so it runs against a
remote ForgeVM host without editing the file.

The `forgevm` SDK is a CLIENT-side library: it runs here (on your machine) and
talks to the ForgeVM server over HTTP. It does not need to be in the sandbox
image.

Run:
    FORGEVM_URL=http://<ip>:7423 uv run --with forgevm python basic.py
"""
import os

from forgevm import Client

FORGEVM_URL = os.environ.get("FORGEVM_URL", "http://localhost:7423")
SANDBOX_IMAGE = os.environ.get("SANDBOX_IMAGE", "alpine:latest")


def main() -> None:
    # Pass api_key="..." to Client(...) if the server has auth enabled.
    with Client(FORGEVM_URL) as client:
        health = client.health()
        print(f"Server status: {health['status']}  version: {health.get('version', 'n/a')}")

        sandbox = client.spawn(image=SANDBOX_IMAGE, ttl="10m")
        print(f"Spawned sandbox: {sandbox.id}  state={sandbox.state}")

        result = sandbox.exec("echo 'Hello from ForgeVM!'")
        print(f"Exit code: {result.exit_code}")
        print(f"Stdout: {result.stdout.strip()}")

        sandbox.write_file("/tmp/greeting.txt", "Hello, world!\n")
        print("Wrote /tmp/greeting.txt")

        content = sandbox.read_file("/tmp/greeting.txt")
        print(f"Read back: {content.strip()!r}")

        files = sandbox.list_files("/tmp")
        print(f"Files in /tmp: {[f['path'] for f in files]}")

        sandbox.destroy()
        print(f"Sandbox {sandbox.id} destroyed.")


if __name__ == "__main__":
    main()

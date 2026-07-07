#!/usr/bin/env python3
"""Streaming exec example using the ForgeVM Python SDK.

Adapted from the upstream ForgeVM examples (MIT) —
https://github.com/DohaerisAI/forgevm/tree/main/examples/python — to read the
server URL and sandbox image from environment variables.

Run:
    FORGEVM_URL=http://<ip>:7423 uv run --with forgevm python streaming.py
"""
import os
import sys

from forgevm import Client

FORGEVM_URL = os.environ.get("FORGEVM_URL", "http://localhost:7423")
SANDBOX_IMAGE = os.environ.get("SANDBOX_IMAGE", "alpine:latest")


def main() -> None:
    with Client(FORGEVM_URL) as client:
        # Context manager destroys the sandbox on exit, even on exception.
        with client.spawn(image=SANDBOX_IMAGE, ttl="5m") as sandbox:
            print(f"Sandbox {sandbox.id} ready.\n")

            # --- Example 1: Stream a simple counting loop ---------------
            print("=== Counting to 5 ===")
            for chunk in sandbox.exec_stream("for i in 1 2 3 4 5; do echo $i; sleep 0.2; done"):
                # chunk.stream is "stdout" or "stderr"; chunk.data is the text.
                sys.stdout.write(chunk.data)
            print()

            # --- Example 2: Interleaved stdout and stderr ---------------
            print("=== Interleaved stdout/stderr ===")
            script = (
                "echo 'out 1'; echo 'err 1' >&2; "
                "echo 'out 2'; echo 'err 2' >&2"
            )
            for chunk in sandbox.exec_stream(script):
                prefix = "[stdout]" if chunk.stream == "stdout" else "[stderr]"
                sys.stdout.write(f"{prefix} {chunk.data}")
            print()

            # --- Example 3: Long-running process ------------------------
            print("=== Generating data ===")
            sandbox.write_file("/tmp/gen.sh", (
                "#!/bin/sh\n"
                "for i in $(seq 1 20); do\n"
                "  echo \"line $i: $(date +%T)\"\n"
                "  sleep 0.1\n"
                "done\n"
            ), mode="0755")

            for chunk in sandbox.exec_stream("sh /tmp/gen.sh"):
                sys.stdout.write(chunk.data)
            print()

        print("Sandbox destroyed (context manager).")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Streaming exec example using the ForgeVM Python SDK.

Adapted from the upstream ForgeVM examples (MIT) —
https://github.com/DohaerisAI/forgevm/tree/main/examples/python — to read the
server URL and sandbox image from environment variables.

WORKAROUND for an upstream SDK/server bug: the *third* streaming request issued
over a reused (keep-alive) connection hangs before response headers arrive
(httpx.ReadTimeout). The first exec_stream on a fresh connection always works.
So each demo below uses its OWN fresh Client (fresh connection pool) and its own
sandbox. That costs a few extra spawns but is reliable. If you only ever do a
single stream per Client, you won't hit the bug.

Run:
    FORGEVM_URL=http://<ip>:7423 uv run --with forgevm python streaming.py
"""
import os
import sys

from forgevm import Client

FORGEVM_URL = os.environ.get("FORGEVM_URL", "http://localhost:7423")
SANDBOX_IMAGE = os.environ.get("SANDBOX_IMAGE", "alpine:latest")


def stream_demo(title: str, command: str, tag_streams: bool = False) -> None:
    """Stream one command in a fresh Client + sandbox (see module docstring)."""
    print(f"=== {title} ===")
    with Client(FORGEVM_URL) as client:
        with client.spawn(image=SANDBOX_IMAGE, ttl="5m") as sandbox:
            for chunk in sandbox.exec_stream(command):
                # chunk.stream is "stdout" or "stderr"; chunk.data is the text.
                if tag_streams:
                    tag = "[stdout]" if chunk.stream == "stdout" else "[stderr]"
                    sys.stdout.write(f"{tag} {chunk.data}")
                else:
                    sys.stdout.write(chunk.data)
    print()


def main() -> None:
    # 1. A simple counting loop, streamed line by line.
    stream_demo(
        "Counting to 5",
        "for i in 1 2 3 4 5; do echo $i; sleep 0.2; done",
    )

    # 2. Interleaved stdout and stderr, tagged as they arrive.
    stream_demo(
        "Interleaved stdout/stderr",
        "echo 'out 1'; echo 'err 1' >&2; echo 'out 2'; echo 'err 2' >&2",
        tag_streams=True,
    )

    # 3. A longer-running process, streamed in real time.
    stream_demo(
        "Generating data",
        "for i in $(seq 1 20); do echo \"line $i: $(date +%T)\"; sleep 0.1; done",
    )

    print("Done (sandboxes destroyed via context managers).")


if __name__ == "__main__":
    main()

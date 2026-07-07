#!/usr/bin/env python3
"""Ollama + ForgeVM agentic loop.

A local Ollama model writes Python to solve a task; the code runs in an isolated
ForgeVM microVM; its output is fed back to the model for up to 3 self-correcting
attempts.

Adapted from the upstream ForgeVM examples (MIT) —
https://github.com/DohaerisAI/forgevm/tree/main/examples/python — to read all
configuration from environment variables so it works against a remote ForgeVM
host and any local Ollama model without editing the file.

Env vars:
    FORGEVM_URL     ForgeVM server         (default http://localhost:7423)
    OLLAMA_URL      Ollama server          (default http://localhost:11434)
    OLLAMA_MODEL    Ollama model tag       (default llama3; e.g. qwen3.5:9b)
    SANDBOX_IMAGE   image to run code in   (default python:3.12-slim)

The SANDBOX_IMAGE MUST contain python3 — Alpine does not, so the upstream
default won't run Python. python:3.12-slim pulls automatically on first use;
forgevm-python:latest (built via ../build.sh) is faster if pre-built.

Ollama runs on your machine (localhost:11434) and is hit directly over HTTP —
OpenJarvis / `uv run jarvis` is NOT involved; you just need `ollama serve` up
with your model pulled.

Run:
    FORGEVM_URL=http://<ip>:7423 OLLAMA_MODEL=qwen3.5:9b \
      uv run --with forgevm python ollama_agent.py "your task here"
"""
from __future__ import annotations

import os
import re
import sys

import httpx

from forgevm import Client

# ---------------------------------------------------------------------------
# Configuration (all overridable via environment variables)
# ---------------------------------------------------------------------------
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3")
FORGEVM_URL = os.environ.get("FORGEVM_URL", "http://localhost:7423")
SANDBOX_IMAGE = os.environ.get("SANDBOX_IMAGE", "python:3.12-slim")

SYSTEM_PROMPT = """\
You are a helpful coding assistant. When the user asks you to solve a task,
respond ONLY with a single Python script that prints the answer to stdout.
Wrap the code in ```python ... ``` markers and output nothing before or after
those markers. Always include the closing ``` marker. Do not include any
explanation outside of code comments.
"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def ask_ollama(prompt: str, history: list[dict]) -> str:
    """Send a chat message to Ollama and return the assistant reply."""
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    messages.extend(history)
    messages.append({"role": "user", "content": prompt})

    resp = httpx.post(
        f"{OLLAMA_URL}/api/chat",
        json={"model": OLLAMA_MODEL, "messages": messages, "stream": False},
        timeout=120.0,
    )
    resp.raise_for_status()
    reply = resp.json()["message"]["content"]
    history.append({"role": "user", "content": prompt})
    history.append({"role": "assistant", "content": reply})
    return reply


def extract_code(reply: str) -> str | None:
    """Extract a Python code block from the LLM reply.

    Tolerant of things small local models do: <think>...</think> reasoning
    blocks, ```py / bare ``` fences, and an UNTERMINATED fence (some models
    forget the closing ```), in which case we take everything to the end.
    """
    reply = re.sub(r"<think>.*?</think>", "", reply, flags=re.DOTALL)
    for marker in ("```python", "```py", "```"):
        start = reply.find(marker)
        if start == -1:
            continue
        start += len(marker)
        end = reply.find("```", start)
        code = (reply[start:end] if end != -1 else reply[start:]).strip()
        if code:
            return code
    return None


# ---------------------------------------------------------------------------
# Main agent loop
# ---------------------------------------------------------------------------


def main() -> None:
    task = (
        "Write a Python script that computes the first 20 Fibonacci numbers "
        "and prints them as a comma-separated list."
    )
    if len(sys.argv) > 1:
        task = " ".join(sys.argv[1:])

    print(f"Task: {task}\n")
    print(f"(ForgeVM={FORGEVM_URL}  Ollama={OLLAMA_MODEL}  image={SANDBOX_IMAGE})\n")

    history: list[dict] = []
    # Initialized so the retry prompt never references an unset variable when an
    # attempt fails to yield runnable code. exit_code is None => "no code yet".
    stdout, stderr, exit_code = "", "", None

    with Client(FORGEVM_URL) as client:
        with client.spawn(image=SANDBOX_IMAGE, ttl="10m") as sandbox:
            print(f"Sandbox {sandbox.id} ready.\n")

            for attempt in range(1, 4):
                print(f"--- Attempt {attempt} ---")

                # 1. Ask the LLM to generate code.
                if attempt == 1:
                    prompt = task
                elif exit_code is None:
                    # Previous attempt produced no runnable code block.
                    prompt = (
                        "You did not return a valid Python code block. Reply with "
                        "ONLY a Python script wrapped in ```python ... ``` that "
                        "prints the answer, including the closing ``` marker."
                    )
                else:
                    prompt = (
                        f"The previous code had this output:\n"
                        f"stdout: {stdout!r}\n"
                        f"stderr: {stderr!r}\n"
                        f"exit code: {exit_code}\n"
                        f"Please fix the script."
                    )

                print("Asking Ollama...")
                reply = ask_ollama(prompt, history)

                code = extract_code(reply)
                if code is None:
                    print("LLM did not return a usable code block. Raw reply:")
                    print(reply)
                    exit_code = None  # keep this attempt marked as "no code"
                    continue

                print(f"Generated code:\n{code}\n")

                # 2. Write the code into the sandbox.
                sandbox.write_file("/tmp/solution.py", code)

                # 3. Execute it.
                result = sandbox.exec("python3 /tmp/solution.py")
                stdout = result.stdout
                stderr = result.stderr
                exit_code = result.exit_code

                print(f"Exit code: {exit_code}")
                if stdout:
                    print(f"Stdout:\n{stdout}")
                if stderr:
                    print(f"Stderr:\n{stderr}")

                # 4. Success?
                if exit_code == 0 and stdout.strip():
                    print("\nTask completed successfully.")
                    break
            else:
                print("\nFailed to produce a working solution after 3 attempts.")

        print("Sandbox destroyed.")


if __name__ == "__main__":
    main()

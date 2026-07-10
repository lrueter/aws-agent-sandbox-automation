# ForgeVM Python SDK examples

The official ForgeVM SDK examples, adapted to read their configuration from
environment variables so they run against **your remote ForgeVM host** without
editing the files.

Originals: <https://github.com/DohaerisAI/forgevm/tree/main/examples/python>
(MIT). Changes here: server URL / model / image are read from env vars.

| File | What it shows |
|------|---------------|
| `basic.py` | spawn → exec → write/read files → destroy |
| `streaming.py` | real-time streamed command output (`exec_stream`) |
| `ollama_agent.py` | agentic loop: local Ollama writes code → runs in a sandbox → self-corrects |

## Key concept: the SDK runs on your machine, not in the sandbox

`from forgevm import Client` is a **client-side HTTP library**. It runs where you
launch the script and talks to the ForgeVM server over the network. You do **not**
bake it into the sandbox image. The sandbox image only needs what the *executed
code* imports (e.g. `python3`, and any libraries that code uses).

## Setup

Nothing to install globally — [`uv`](https://docs.astral.sh/uv/) runs each script
in a throwaway environment with the SDK:

```bash
uv run --with forgevm python basic.py
```

Point the scripts at your server (from the repo, `terraform -chdir=terraform
output -raw public_ip` gives the IP):

```bash
export FORGEVM_URL="http://<public_ip>:7423"
```

> Run these from *this* directory, not from another `uv`/Python project, so
> `uv run --with` builds a clean environment.

## Run them

```bash
# 1. Basic SDK round-trip (Alpine is fine — only runs shell commands):
FORGEVM_URL="http://<ip>:7423" uv run --with forgevm python basic.py

# 2. Streaming output:
FORGEVM_URL="http://<ip>:7423" uv run --with forgevm python streaming.py

# 3. Ollama agent — needs a python3 image and a running Ollama model.
#    (Ollama runs on your Mac at :11434; OpenJarvis is not involved.)
FORGEVM_URL="http://<ip>:7423" \
OLLAMA_MODEL="qwen3.5:9b" \
SANDBOX_IMAGE="forgevm-python:latest" \
uv run --with forgevm python ollama_agent.py "compute the 100th prime number"
```

### Choosing `SANDBOX_IMAGE` for the agent

The agent runs `python3 /tmp/solution.py`, so the image **must contain python3**
(Alpine does not):

- `python:3.12-slim` (default) — public image, pulled+built on first spawn (slower first time).
- `forgevm-python:latest` — the image from [`../`](../) (python + pandas), fast if
  you've already run `../build.sh` on the host.

## Prerequisites checklist

```bash
curl -sS http://<ip>:7423/api/v1/sandboxes   # ForgeVM up → []
ollama list                                   # your model is listed (note exact tag)
curl -sS http://localhost:11434/api/tags >/dev/null && echo "ollama up"
```

## Troubleshooting

- **`ModuleNotFoundError: forgevm`** — use the `uv run --with forgevm ...` wrapper,
  and run from this directory (not another project).
- **`python3: not found` in the agent** — `SANDBOX_IMAGE` is an image without
  Python (e.g. Alpine). Use `forgevm-python:latest` or `python:3.12-slim`.
- **`LLM did not return a code block`** — the model didn't wrap its answer in
  ```` ```python ```` fences; it will retry. Smaller/thinking models sometimes need
  a firmer task prompt.
- **Connection refused :7423** — wrong/old `FORGEVM_URL` (a rebuild changes the IP).
- **Connection refused :11434** — Ollama isn't serving; run `ollama serve`.

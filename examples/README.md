# Running Python-with-dependencies in ForgeVM

ForgeVM sandboxes boot from a Docker image and, by default, have **no network
access** (`Network: none`). So the reliable way to use third-party libraries is
to **bake them into the image**, not `pip install` at runtime.

This folder is a copy-paste starting point for that pattern.

```
examples/
  Dockerfile         python:3.12-slim + your requirements
  requirements.txt   the libraries to bake in (edit this)
  app/analyze.py     sample workload (uses pandas to prove deps are present)
  build.sh           run ON THE HOST: docker build + forgevm build-image
  run.py             run FROM YOUR MAC: spawn → upload → exec → cleanup (stdlib only)
  run.sh             same as run.py, in curl + jq
```

## Workflow

### 1. Add your libraries

Edit `requirements.txt` (pin versions for reproducibility).

### 2. Build the image on the ForgeVM host

```bash
# copy this folder to the host (or git clone the repo there), then:
ssh -i ../forgevm-ssh-key.pem ec2-user@<public_ip>
cd examples
./build.sh                      # builds forgevm-python:latest and its rootfs
# or: ./build.sh myteam-ml:latest
```

`build.sh` runs `docker build` then `forgevm build-image`, which caches an ext4
rootfs so later spawns are fast (snapshot restore).

### 3. Run your code from your Mac

```bash
FORGEVM_URL=http://<public_ip>:7423 IMAGE=forgevm-python:latest python3 run.py
# or the curl version:
FORGEVM_URL=http://<public_ip>:7423 IMAGE=forgevm-python:latest ./run.sh
```

Expected output includes the exec result showing the pandas version and computed
values — proof the dependency is available inside the microVM with no network.

## Alternative: install at runtime (needs network)

For quick iteration you can skip image rebuilds by enabling outbound network on
the sandbox and installing at runtime — at the cost of weaker isolation and a
download on every run:

```python
sb = client.spawn(image="python:3.12", network="egress")  # opt into outbound
sb.exec("pip install pandas")
sb.exec("python3 /app/analyze.py")
```

Confirm the exact network-mode parameter against ForgeVM's API docs. Prefer the
baked-image approach for anything repeated or untrusted.

## Notes

- The `/files` and `/exec` payload shapes in `run.py` / `run.sh` are inferred
  from ForgeVM's docs; both scripts print raw responses, so if your ForgeVM
  version differs you'll see it and can adjust the JSON fields.
- If the server is configured with an API key, set `FORGEVM_API_KEY` (run.py
  sends it as a Bearer token).
- Heavier workloads may need more than the default 1 vCPU / 1024 MB — pass
  larger `memory_mb` / `vcpus` on spawn if your SDK/API exposes them.

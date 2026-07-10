#!/usr/bin/env python3
"""
Spawn a ForgeVM sandbox from a dependency-baked image, upload a script, run it,
and clean up. Talks to the ForgeVM REST API directly using only the Python
standard library (nothing to pip install on your machine).

Run from your Mac, pointing at the server:
    FORGEVM_URL=http://<ip>:7423 IMAGE=forgevm-python:latest python3 run.py

Env vars:
    FORGEVM_URL      base URL of the ForgeVM API (default http://localhost:7423)
    IMAGE            image to spawn from     (default forgevm-python:latest)
    FORGEVM_API_KEY  optional; sent as a Bearer token if the server requires auth

NOTE: the /files and /exec request/response shapes are inferred from ForgeVM's
docs. Every response is printed raw, so if your ForgeVM version uses different
field names, you'll see it immediately and can tweak the payloads below.
"""
import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("FORGEVM_URL", "http://localhost:7423").rstrip("/")
IMAGE = os.environ.get("IMAGE", "forgevm-python:latest")
API_KEY = os.environ.get("FORGEVM_API_KEY")

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL_SCRIPT = os.path.join(HERE, "app", "analyze.py")
REMOTE_PATH = "/app/analyze.py"


def call(method, path, body=None):
    """Make one API call; return (status_code, parsed_json_or_text)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if API_KEY:
        req.add_header("Authorization", "Bearer " + API_KEY)
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach {BASE}: {e.reason}")


def main():
    with open(LOCAL_SCRIPT) as f:
        code = f.read()

    print(f"→ spawn sandbox  image={IMAGE}  at {BASE}")
    status, sb = call("POST", "/api/v1/sandboxes", {"image": IMAGE})
    print(f"  [{status}] {json.dumps(sb) if isinstance(sb, dict) else sb}")
    if not isinstance(sb, dict) or "id" not in sb:
        blob = sb if isinstance(sb, str) else json.dumps(sb)
        if "pull access denied" in blob or "repository does not exist" in blob:
            sys.exit(
                f"\nImage '{IMAGE}' isn't on the ForgeVM host yet, so it tried to\n"
                f"pull it from Docker Hub and failed. Build it on the host first:\n"
                f"  scp -i <key.pem> -r . ec2-user@<host>:~/examples\n"
                f"  ssh -i <key.pem> ec2-user@<host> 'cd ~/examples && ./build.sh'\n"
                f"...then re-run. (Or set IMAGE= to a public image that already\n"
                f"contains your dependencies.)"
            )
        sys.exit("spawn failed (see response above)")
    sid = sb["id"]

    try:
        print(f"→ upload {REMOTE_PATH}")
        status, resp = call(
            "POST", f"/api/v1/sandboxes/{sid}/files",
            {"path": REMOTE_PATH, "content": code},
        )
        print(f"  [{status}] {resp}")

        print(f"→ exec  python3 {REMOTE_PATH}")
        status, resp = call(
            "POST", f"/api/v1/sandboxes/{sid}/exec",
            {"command": f"python3 {REMOTE_PATH}"},
        )
        print(f"  [{status}] {resp}")
    finally:
        print(f"→ delete sandbox {sid}")
        status, resp = call("DELETE", f"/api/v1/sandboxes/{sid}")
        print(f"  [{status}] {resp}")


if __name__ == "__main__":
    main()

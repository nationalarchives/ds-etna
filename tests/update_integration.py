"""Isolated Docker handoff test using local nginx and Python images."""

import concurrent.futures
import json
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import time
import urllib.request
import uuid


ROOT = Path(__file__).resolve().parents[1]
SERVER = """
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket
import time

started = time.monotonic()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health" and (
            time.monotonic() - started < 3 or Path("/control/unhealthy").exists()
        ):
            self.send_response(503)
            self.end_headers()
            return
        if self.path in ("/chat/hold", "/status/hold"):
            Path("/control/holding").touch()
            time.sleep(8)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(socket.gethostname().encode())

    def log_message(self, *args):
        pass

ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
"""


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def main():
    project = f"etna-handoff-test-{uuid.uuid4().hex[:8]}"
    with tempfile.TemporaryDirectory(prefix=project) as temporary:
        directory = Path(temporary)
        (directory / "server.py").write_text(SERVER)
        control = directory / "control"
        control.mkdir()
        certificates = directory / "certificates"
        certificates.mkdir()
        run(
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(certificates / "privkey.pem"),
            "-out", str(certificates / "fullchain.pem"),
            "-days", "1", "-subj", "/CN=localhost",
            stderr=subprocess.DEVNULL,
        )
        app = {
            "image": "python:3.14-slim-trixie",
            "command": ["python", "/server.py"],
            "volumes": [
                f"{directory / 'server.py'}:/server.py:ro",
                f"{control}:/control",
            ],
            "healthcheck": {
                "test": [
                    "CMD", "python", "-c",
                    "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')",
                ],
                "interval": "1s", "timeout": "1s",
                "start_period": "5s", "retries": 1,
            },
        }
        config = {
            "services": {
                "service-status": app,
                "chat": {
                    **app,
                    "container_name": f"{project}-original-chat",
                    "networks": {"default": {"aliases": ["uptime-kuma", "portainer"]}},
                },
                "nginx": {
                    "image": "nginx:latest",
                    "command": [
                        "nginx", "-c", "/etc/nginx/etna-conf/nginx.conf",
                        "-g", "daemon off;",
                    ],
                    "depends_on": {
                        name: {"condition": "service_healthy"}
                        for name in ("service-status", "chat")
                    },
                    "ports": ["127.0.0.1::443"],
                    "volumes": [
                        f"{ROOT / 'conf'}:/etc/nginx/etna-conf:ro",
                        f"{ROOT / 'conf/10-etna-upstreams.sh'}:/docker-entrypoint.d/10-etna-upstreams.sh:ro",
                        *[
                            f"{certificates}:/etc/nginx/ssl/live/{domain}:ro"
                            for domain in (
                                "tna.dblclk.dev", "chat.tna.dblclk.dev",
                                "uptime.tna.dblclk.dev",
                                "portainer.tna.dblclk.dev",
                            )
                        ],
                    ],
                },
            },
        }
        compose_file = directory / "compose.json"
        compose_file.write_text(json.dumps(config))
        compose = ["docker", "compose", "-p", project, "-f", str(compose_file)]

        def containers(service="chat"):
            return run(*compose, "ps", "--all", "--quiet", service).splitlines()

        def running(container):
            return run("docker", "inspect", "-f", "{{.State.Running}}", container) == "true"

        try:
            subprocess.run([*compose, "up", "-d", "--wait", "--wait-timeout", "60"], check=True)
            nginx = run(*compose, "ps", "--quiet", "nginx")
            port = run(*compose, "port", "nginx", "443").rsplit(":", 1)[1]
            # Simulate upgrading from the old fixed-name application service.
            del config["services"]["chat"]["container_name"]
            compose_file.write_text(json.dumps(config))
            context = ssl._create_unverified_context()

            def request(path="/chat", host="tna.dblclk.dev"):
                with urllib.request.urlopen(
                    urllib.request.Request(
                        f"https://localhost:{port}{path}", headers={"Host": host}
                    ), context=context, timeout=15
                ) as response:
                    assert response.status == 200
                    return response.read().decode()

            def deploy(service, drain_timeout=30):
                # Redirect only the script's fixed nginx handle into this test project.
                command = """
source "$REPOSITORY/update.sh"
docker() {
  if [[ "$1" == compose ]]; then
    shift
    command docker compose -p "$TEST_PROJECT" -f "$TEST_COMPOSE" "$@"
  elif [[ "$1" == exec ]]; then
    shift
    if [[ "$1" == -i ]]; then
      shift
      command docker exec -i "$TEST_NGINX" "${@:2}"
    else
      command docker exec "$TEST_NGINX" "${@:2}"
    fi
  elif [[ "$1" == inspect && "${@: -1}" == nginx ]]; then
    command docker "${@:1:$#-1}" "$TEST_NGINX"
  else
    command docker "$@"
  fi
}
zero_downtime_deploy "$TEST_SERVICE"
"""
                return subprocess.Popen(
                    ["bash", "-c", command],
                    env={
                        **os.environ, "REPOSITORY": str(ROOT),
                        "TEST_PROJECT": project, "TEST_COMPOSE": str(compose_file),
                        "TEST_NGINX": nginx, "HEALTHCHECK_TIMEOUT": "20",
                        "TEST_SERVICE": service,
                        "NGINX_DRAIN_TIMEOUT": str(drain_timeout),
                    },
                )

            status_response = request("/status")
            for scenario in ("healthy", "healthy-status", "unhealthy", "missing-health", "drain-timeout"):
                service = "service-status" if scenario == "healthy-status" else "chat"
                path = "/status" if service == "service-status" else "/chat"
                original = containers(service)[0]
                original_response = request(path)
                if service == "chat":
                    assert request("/", "chat.tna.dblclk.dev") == original_response
                if scenario == "unhealthy":
                    (control / "unhealthy").touch()
                if scenario == "missing-health":
                    config["services"]["chat"]["healthcheck"] = {"disable": True}
                    compose_file.write_text(json.dumps(config))

                with concurrent.futures.ThreadPoolExecutor() as executor:
                    held = None
                    if scenario.startswith("healthy") or scenario == "drain-timeout":
                        held = executor.submit(request, f"{path}/hold")
                        deadline = time.monotonic() + 5
                        while not (control / "holding").exists():
                            assert time.monotonic() < deadline, "Held request never started"
                            time.sleep(0.05)
                    process = deploy(service, 1 if scenario == "drain-timeout" else 30)
                    deadline = time.monotonic() + 40
                    requests = 0
                    switched = False
                    try:
                        while process.poll() is None:
                            assert time.monotonic() < deadline, "Deployment timed out"
                            response = request(path)
                            requests += 1
                            if response != original_response and not switched:
                                switched = True
                                replacement = next(c for c in containers(service) if c != original)
                                health = run(
                                    "docker", "inspect", "-f",
                                    "{{.State.Health.Status}}", replacement,
                                )
                                assert health == "healthy", "Traffic switched before healthcheck passed"
                                assert running(original), "Original removed before handoff"
                            time.sleep(0.05)
                    finally:
                        if process.poll() is None:
                            process.terminate()
                            process.wait(timeout=10)

                    if scenario.startswith("healthy"):
                        assert process.returncode == 0
                        assert switched and len(containers(service)) == 1
                        assert held.result() == original_response, "In-flight request was interrupted"
                    else:
                        assert process.returncode != 0
                        assert running(original) and len(containers(service)) == 2
                        if scenario != "drain-timeout":
                            assert not switched
                        else:
                            assert switched
                            assert held.result() == original_response
                    print(f"PASS: {scenario}, {requests} successful requests", flush=True)
                    if scenario == "healthy-status":
                        status_response = request("/status")
                        assert status_response != original_response
                    else:
                        assert request("/status") == status_response

                # Restore a single healthy baseline after each failed test.
                for container in containers(service):
                    if not scenario.startswith("healthy") and container != original:
                        run("docker", "rm", "-f", container)
                if scenario == "drain-timeout":
                    break
                (control / "unhealthy").unlink(missing_ok=True)
                (control / "holding").unlink(missing_ok=True)
                config["services"]["chat"]["healthcheck"] = app["healthcheck"]
                compose_file.write_text(json.dumps(config))
        except Exception:
            subprocess.run([*compose, "logs", "--tail", "30", "nginx"], check=True)
            raise
        finally:
            subprocess.run([*compose, "down", "--volumes", "--remove-orphans"], check=True)


if __name__ == "__main__":
    main()

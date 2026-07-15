import os
import sys
import json
from http.client import HTTPSConnection
from urllib.parse import urlparse

API_KEY = os.environ.get("ZEN_API_KEY", "")
BASE = "https://opencode.ai/zen/v1/chat/completions"


def ask_ai(current_yml, error_logs):
    system = (
        "You are a GitHub Actions CI expert. A CodeQL workflow failed.\n"
        "Your job: analyze the failure and return a FIXED version of the workflow YAML.\n\n"
        "RULES:\n"
        "- Return ONLY valid YAML. No markdown fences, no explanations, no comments.\n"
        "- Keep the workflow name as 'CodeQL Advanced'.\n"
        "- Keep triggers (push/PR/schedule) unchanged.\n"
        "- Fix whatever caused the failure (resource limits, config errors, etc).\n"
        "- If the runner crashed from OOM/timeout: reduce scope, add paths filters, lower RAM usage.\n"
        "- If SARIF upload failed: set upload: false.\n"
        "- Always include: timeout-minutes, fail-fast: false, extractor-options if C/C++.\n"
        "- The matrix must include language: c-cpp with build-mode: none.\n"
        "- Do NOT add unnecessary steps. Keep it minimal and working."
    )

    user = (
        f"Current workflow (codeql.yml):\n```yaml\n{current_yml}\n```\n\n"
        f"Error logs from failed run:\n```\n{error_logs[:8000]}\n```\n\n"
        "Return the COMPLETE fixed codeql.yml YAML. Nothing else."
    )

    body = json.dumps({
        "model": "big-pickle",
        "max_tokens": 4000,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user}
        ],
        "stream": False
    })

    parsed = urlparse(BASE)
    conn = HTTPSConnection(parsed.hostname, 443, timeout=120)
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
    }
    conn.request("POST", parsed.path, body=body, headers=headers)
    resp = conn.getresponse()
    data = json.loads(resp.read().decode())

    content = data["choices"][0]["message"]["content"]

    # Strip markdown fences if present
    if content.startswith("```"):
        lines = content.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        content = "\n".join(lines)

    return content.strip()


if __name__ == "__main__":
    with open("/tmp/current.yml") as f:
        current = f.read()
    with open("/tmp/errors.txt") as f:
        errors = f.read()

    result = ask_ai(current, errors)

    # Validate it looks like YAML
    if not any(k in result for k in ["name:", "on:", "jobs:"]):
        print("ERROR: AI response does not look like valid YAML", file=sys.stderr)
        print(result[:500], file=sys.stderr)
        sys.exit(1)

    with open("/tmp/fixed.yml", "w") as f:
        f.write(result)

    print("AI produced fixed workflow (" + str(len(result)) + " bytes)")

#!/usr/bin/env python3
"""Talking to a model, and nothing else.

**This never runs inside the game.** Endless Frontier is offline-first — there
is no URLSession in the simulation path and no key shipped in the app. These
tools run on a workstation, write JSON, and the JSON is what ships. If anything
here ever ends up being called at play time, the rule has been broken.

The transport is lifted from `Diy-app/tools/translate.py`, which has already
survived a six-hundred-batch run: the `.env` loading, the two shapes of Google
key, the JSON response mode, and the retry table are all things that were
learned the expensive way over there. Copying a working one beats writing a
second one that has to learn the same lessons again.
"""

from __future__ import annotations

import json
import os
import ssl
import random
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"


def load_env_file(path: Path = ENV_FILE) -> None:
    """Read `KEY=value` lines from `.env` without overriding the real thing.

    `export` only lives in the shell that ran it, so a key set in one terminal
    is gone from the next — which looks exactly like a broken key. A variable
    already set in the environment always wins.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        name = name.removeprefix("export ").strip()
        value = value.strip().strip("'\"")
        if name and name not in os.environ:
            os.environ[name] = value


load_env_file()

# Which vendor answers. All three speak the same contract as far as everything
# above this module is concerned: a prompt in, a JSON document out.
#
# Vertex is the default because it is the one that needs no secret: it signs
# each call with a short-lived `gcloud` token and bills the project. The two
# key-based backends are there for a workstation without gcloud, and defaulting
# to one of those would mean a lost `.env` fails as "API_KEY_INVALID" rather
# than as "you are not logged in", which sends you looking in the wrong place.


# macOS ships several Pythons and they do not agree about certificates: the
# python.org framework build looks for a `cert.pem` under its own prefix that a
# plain installer never creates, so the same script that worked this morning
# fails with CERTIFICATE_VERIFY_FAILED this afternoon purely because `python3`
# resolved somewhere else. The system bundle at /etc/ssl/cert.pem is always
# there and always current, so use it when the interpreter's own is missing.
def _certificates() -> ssl.SSLContext:
    configured = ssl.get_default_verify_paths().openssl_cafile
    if configured and Path(configured).exists():
        return ssl.create_default_context()
    for fallback in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
        if Path(fallback).exists():
            return ssl.create_default_context(cafile=fallback)
    # Never fall back to an unverified context: this posts the project's own
    # content to a Google endpoint under the user's credentials, and skipping
    # verification to make an error go away is how that becomes somebody else's
    # endpoint.
    raise SystemExit(
        "No usable CA bundle. Install certificates for this Python "
        "(Applications/Python 3.x/Install Certificates.command) or set "
        "SSL_CERT_FILE."
    )


SSL_CONTEXT = _certificates()

BACKEND = os.environ.get("EF_BACKEND", "vertex").lower()

DEFAULT_MODEL = {
    "gemini": "gemini-2.5-flash",
    "vertex": "gemini-2.5-flash",
    "anthropic": "claude-sonnet-5",
}
MODEL = os.environ.get("EF_MODEL", DEFAULT_MODEL.get(BACKEND, "gemini-2.5-flash"))


def use_model(name: str | None) -> None:
    """Point the next call at a different model.

    Flash writes the volume — items, meals, the flavour half of the events —
    at a price where a thousand entries is not a decision. Pro is worth it
    where the *shape* is the hard part rather than the prose: a law that has to
    cost somebody something, a tech that has to sit correctly in the DAG. One
    run should be able to choose without a second terminal and an export.
    """
    global MODEL
    if name:
        MODEL = name

ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

KEY_VARIABLES = {
    "anthropic": ("ANTHROPIC_API_KEY",),
    "gemini": ("GEMINI_API_KEY", "GOOGLE_API_KEY"),
}

# Vertex bills the project's Cloud credits and authenticates with a short-lived
# OAuth token from gcloud rather than a long-lived key, so nothing secret is
# stored anywhere in the repository.
VERTEX_PROJECT = os.environ.get("GOOGLE_CLOUD_PROJECT", "")
VERTEX_LOCATION = os.environ.get("GOOGLE_CLOUD_LOCATION", "global")
VERTEX_HOST = (
    "aiplatform.googleapis.com"
    if VERTEX_LOCATION == "global"
    else f"{VERTEX_LOCATION}-aiplatform.googleapis.com"
)
VERTEX_URL = (
    "https://{host}/v1/projects/{project}/locations/{location}"
    "/publishers/google/models/{model}:generateContent"
)

MAX_ATTEMPTS = 5
_vertex_token: tuple[str, float] | None = None


def api_key() -> str:
    """The key for the chosen backend, or a sentence saying which one is missing."""
    if BACKEND == "vertex":
        if not VERTEX_PROJECT:
            raise SystemExit("Vertex needs GOOGLE_CLOUD_PROJECT (put it in .env)")
        return VERTEX_PROJECT
    names = KEY_VARIABLES.get(BACKEND, ())
    for name in names:
        if os.environ.get(name):
            return os.environ[name]
    raise SystemExit(f"{BACKEND} needs one of {' / '.join(names)} — put it in .env")


def vertex_token() -> str:
    """A gcloud access token, refreshed well before its hour is up."""
    global _vertex_token
    now = time.time()
    if _vertex_token and _vertex_token[1] > now:
        return _vertex_token[0]
    token = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    _vertex_token = (token, now + 45 * 60)
    return token


def invalidate_vertex_token() -> None:
    global _vertex_token
    _vertex_token = None


def post_json(url: str, body: dict, headers: dict[str, str]) -> dict:
    """POST and decode, but never swallow the reason a request was rejected.

    urllib prints an HTTPError as a bare "400: Bad Request" while the body holds
    the sentence that actually explains it — a bad key, a model name that does
    not exist, a payload the vendor would not take. Losing that turns a
    one-minute fix into guesswork.
    """
    request = urllib.request.Request(
        url, data=json.dumps(body).encode("utf-8"), headers=headers
    )
    try:
        with urllib.request.urlopen(request, timeout=600, context=SSL_CONTEXT) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            detail = error.read().decode("utf-8", "replace").strip()
        except Exception:  # noqa: BLE001 — the original error still has to win
            pass
        if detail:
            raise urllib.error.HTTPError(
                error.url, error.code, f"{error.reason}: {detail[:600]}",
                error.headers, None,
            ) from None
        raise


def gemini_headers(key: str) -> dict[str, str]:
    """Google is mid-migration between two kinds of key and they authenticate
    differently. Legacy traffic keys (`AIza...`) go in `x-goog-api-key`; the
    newer authentication keys (`AQ....`) AI Studio now issues are bearer
    credentials. Sending the wrong one comes back as a flat 400 API_KEY_INVALID,
    which reads like a typo rather than a format mismatch."""
    headers = {"content-type": "application/json"}
    if key.startswith("AQ."):
        headers["Authorization"] = f"Bearer {key}"
    else:
        headers["x-goog-api-key"] = key
    return headers


def gemini_body(system: str, user: str, temperature: float, max_tokens: int) -> dict:
    """Gemini takes the system prompt in its own field and can be told to answer
    in JSON, which removes the "model wrapped it in prose" failure mode."""
    return {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "maxOutputTokens": max_tokens,
            "temperature": temperature,
        },
    }


def gemini_text(payload: dict) -> str:
    candidates = payload.get("candidates") or []
    if not candidates:
        # A blocked prompt comes back 200 with no candidate, so it has to be
        # read as a failure here rather than as an empty answer.
        raise ValueError(f"model returned nothing: {json.dumps(payload)[:300]}")
    reason = candidates[0].get("finishReason")
    if reason not in (None, "STOP"):
        raise ValueError(f"model stopped early ({reason})")
    return "".join(
        part.get("text", "") for part in candidates[0].get("content", {}).get("parts", [])
    )


def call_gemini(system: str, user: str, key: str, temperature: float, max_tokens: int) -> str:
    payload = post_json(
        GEMINI_URL.format(model=MODEL),
        gemini_body(system, user, temperature, max_tokens),
        gemini_headers(key),
    )
    return gemini_text(payload)


def call_vertex(system: str, user: str, project: str, temperature: float, max_tokens: int) -> str:
    """The same request as the Gemini API, addressed to the project's own Vertex
    endpoint and signed with an OAuth token instead of a key."""
    url = VERTEX_URL.format(
        host=VERTEX_HOST, project=project, location=VERTEX_LOCATION, model=MODEL
    )
    payload = post_json(
        url,
        gemini_body(system, user, temperature, max_tokens),
        {"content-type": "application/json", "Authorization": f"Bearer {vertex_token()}"},
    )
    return gemini_text(payload)


def call_anthropic(system: str, user: str, key: str, temperature: float, max_tokens: int) -> str:
    payload = post_json(
        ANTHROPIC_URL,
        {
            "model": MODEL,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        },
        {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
    )
    return "".join(part.get("text", "") for part in payload.get("content", []))


def extract_json(text: str):
    """The document the model meant, whatever it wrapped it in."""
    for opener, closer in (("[", "]"), ("{", "}")):
        start, end = text.find(opener), text.rfind(closer)
        if start >= 0 and end > start:
            try:
                return json.loads(text[start : end + 1])
            except json.JSONDecodeError:
                continue
    raise ValueError("model did not return JSON")


def ask(system: str, user: str, temperature: float = 0.9, max_tokens: int = 32000):
    """One prompt in, one parsed JSON document out. Retried, because rate limits
    and overloads are the normal case on a run of any length."""
    key = api_key()
    callers = {"gemini": call_gemini, "vertex": call_vertex, "anthropic": call_anthropic}
    caller = callers.get(BACKEND, call_gemini)
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            return extract_json(caller(system, user, key, temperature, max_tokens))
        except urllib.error.HTTPError as error:
            if error.code == 401:
                # An expired OAuth token is the textbook transient failure, but
                # it only clears if the cached one is thrown away first.
                invalidate_vertex_token()
            retryable = error.code in (401, 408, 429, 500, 502, 503, 504, 529)
            if not retryable or attempt == MAX_ATTEMPTS:
                raise
        except (urllib.error.URLError, TimeoutError, ValueError):
            if attempt == MAX_ATTEMPTS:
                raise
        time.sleep(min(60, 2**attempt) + random.uniform(0, 1))
    raise RuntimeError("unreachable")

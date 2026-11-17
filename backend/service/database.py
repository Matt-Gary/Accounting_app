import os
import threading

import httpx
from dotenv import load_dotenv
from postgrest import SyncPostgrestClient

# Load environment variables from .env file
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env'))

# One client for the whole process. get_pg() used to build a new one on every
# call, and each new client opens its own connection: a dashboard load makes
# several queries one after another and paid a fresh TLS handshake to Supabase
# for every single one of them. A shared client keeps the connection open, so
# only the first query of a burst pays for it.
#
# Safe to share between request threads: httpx.Client is thread-safe and the
# code never mutates the client (no .auth(), no .schema()) - every from_()
# builds its own request.
_client = None
_client_lock = threading.Lock()

# Without a timeout a stalled Supabase call held its request thread forever
# (the library's default is "no limit"). 30 s is far above any query here.
_TIMEOUT = httpx.Timeout(30.0, connect=10.0)

# Idle connections are dropped after 30 s - long enough to cover the pause
# between two taps in the app, short enough to stay well under the server's own
# idle timeout, so a connection is never reused after the far end closed it.
_LIMITS = httpx.Limits(
    max_connections=20,
    max_keepalive_connections=10,
    keepalive_expiry=30.0,
)


def get_pg():
    global _client
    if _client is not None:
        return _client

    with _client_lock:
        # Re-checked under the lock: two threads can both see None above.
        if _client is not None:
            return _client

        url = os.environ.get("SUPABASE_URL")
        key = os.environ.get("SUPABASE_KEY")

        if not url or not key:
            raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in .env file")

        # Ensure URL ends with /rest/v1
        base_url = url.rstrip("/") + "/rest/v1"

        # Created lazily (first query, not import time) so a pre-forking server
        # never hands the same open socket to several worker processes.
        http_client = httpx.Client(
            base_url=base_url,
            timeout=_TIMEOUT,
            limits=_LIMITS,
            follow_redirects=True,
            http2=True,
        )
        _client = SyncPostgrestClient(
            base_url,
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
            },
            http_client=http_client,
        )
        return _client

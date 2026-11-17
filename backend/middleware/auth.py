import hashlib
import os
import threading
import time
from functools import wraps
from flask import request, jsonify, g
from supabase import create_client
from service.database import get_pg

# The single Super Admin. Hard-coded by design: there is exactly one.
SUPER_ADMIN_PROFILE_ID = "e670ba5d-cb22-400d-a9e2-ff81d2902bd3"

# Singleton Supabase client — created once, reused on every request
_supabase_client = None

def get_supabase():
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = create_client(
            os.environ.get("SUPABASE_URL"),
            os.environ.get("SUPABASE_KEY"),
        )
    return _supabase_client


# ── Identity cache ──────────────────────────────────────────────────────────
# Resolving a token costs three network round-trips (Supabase Auth, profiles,
# family_members) and used to run before EVERY request - opening the app fires
# several requests at once, so the same token was resolved again and again.
# A resolved identity is now remembered for a short while.
#
# The price, accepted on purpose: a token revoked at Supabase (sign-out,
# password change) keeps working here for up to _AUTH_CACHE_TTL seconds.
# Keep the TTL short; do not raise it to "save more".
_AUTH_CACHE_TTL = 60.0
_AUTH_CACHE_MAX = 500
_auth_cache = {}  # sha256(token) -> (expires_at, identity)
_auth_cache_lock = threading.Lock()


def _token_key(token):
    # The raw token is a credential; only its digest is kept in memory.
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _cached_identity(key):
    with _auth_cache_lock:
        entry = _auth_cache.get(key)
        if entry is None:
            return None
        if entry[0] <= time.monotonic():
            del _auth_cache[key]
            return None
        return entry[1]


def _remember_identity(key, identity):
    now = time.monotonic()
    with _auth_cache_lock:
        if len(_auth_cache) >= _AUTH_CACHE_MAX:
            # Tokens rotate hourly, so dead entries pile up; drop them first.
            for k in [k for k, v in _auth_cache.items() if v[0] <= now]:
                del _auth_cache[k]
            if len(_auth_cache) >= _AUTH_CACHE_MAX:
                _auth_cache.clear()
        _auth_cache[key] = (now + _AUTH_CACHE_TTL, identity)


def clear_auth_cache():
    """Forget every remembered identity. Call after anything that changes who a
    token maps to (a user or family deleted, an e-mail changed)."""
    with _auth_cache_lock:
        _auth_cache.clear()


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing auth token"}), 401

        token = auth_header[7:]

        cache_key = _token_key(token)
        identity = _cached_identity(cache_key)
        if identity is not None:
            g.user_id = identity["user_id"]
            g.user_email = identity["user_email"]
            g.profile_id = identity["profile_id"]
            g.family_id = identity["family_id"]
            return f(*args, **kwargs)

        try:
            supabase = get_supabase()
            response = supabase.auth.get_user(token)
            user = response.user
            if user is None:
                return jsonify({"error": "Invalid token"}), 401
        except Exception:
            return jsonify({"error": "Invalid token"}), 401

        g.user_id = user.id
        g.user_email = user.email or ""

        client = get_pg()

        profile_res = (
            client.from_("profiles")
            .select("id")
            .eq("auth_id", user.id)
            .limit(1)
            .execute()
        )
        g.profile_id = profile_res.data[0]["id"] if profile_res.data else None

        # Deterministic: oldest membership wins. Multi-family membership is not
        # supported today, but ordering avoids non-deterministic results if a
        # stray duplicate row exists.
        family_res = (
            client.from_("family_members")
            .select("family_id")
            .eq("user_id", user.id)
            .order("created_at", desc=False)
            .limit(1)
            .execute()
        )
        g.family_id = family_res.data[0]["family_id"] if family_res.data else None

        # Only a COMPLETE identity is remembered. A user in the middle of
        # onboarding has no profile/family yet; caching that would keep them
        # "without a family" for a minute after /auth/onboard created one, and
        # routes scope their data by g.family_id.
        if g.profile_id and g.family_id:
            _remember_identity(cache_key, {
                "user_id": g.user_id,
                "user_email": g.user_email,
                "profile_id": g.profile_id,
                "family_id": g.family_id,
            })

        return f(*args, **kwargs)

    return decorated


def require_super_admin(f):
    @wraps(f)
    @require_auth
    def decorated(*args, **kwargs):
        if g.profile_id != SUPER_ADMIN_PROFILE_ID:
            return jsonify({"error": "Forbidden"}), 403
        return f(*args, **kwargs)
    return decorated

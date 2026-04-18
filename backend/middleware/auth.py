import os
from functools import wraps
from flask import request, jsonify, g
from supabase import create_client
from service.database import get_pg

# Singleton Supabase client — created once, reused on every request
_supabase_client = None

def _get_supabase():
    global _supabase_client
    if _supabase_client is None:
        _supabase_client = create_client(
            os.environ.get("SUPABASE_URL"),
            os.environ.get("SUPABASE_KEY"),
        )
    return _supabase_client


# Per-user caches — profile_id and family_id never change, so we cache forever
_profile_cache: dict = {}  # auth_user_id -> profile_id
_family_cache: dict = {}   # auth_user_id -> family_id


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing auth token"}), 401

        token = auth_header[7:]

        try:
            supabase = _get_supabase()
            response = supabase.auth.get_user(token)
            user = response.user
            if user is None:
                return jsonify({"error": "Invalid token"}), 401
        except Exception:
            return jsonify({"error": "Invalid token"}), 401

        g.user_id = user.id
        g.user_email = user.email or ""

        client = get_pg()

        if user.id not in _profile_cache:
            profile_res = (
                client.from_("profiles")
                .select("id")
                .eq("auth_id", user.id)
                .execute()
            )
            _profile_cache[user.id] = profile_res.data[0]["id"] if profile_res.data else None

        if user.id not in _family_cache:
            family_res = (
                client.from_("family_members")
                .select("family_id")
                .eq("user_id", user.id)
                .execute()
            )
            _family_cache[user.id] = family_res.data[0]["family_id"] if family_res.data else None

        g.profile_id = _profile_cache[user.id]
        g.family_id = _family_cache[user.id]

        return f(*args, **kwargs)

    return decorated

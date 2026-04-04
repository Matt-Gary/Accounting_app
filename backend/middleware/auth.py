import os
from functools import wraps
from flask import request, jsonify, g
from supabase import create_client
from service.database import get_pg


def _get_supabase():
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    return create_client(url, key)


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing auth token"}), 401

        token = auth_header[7:]  # Strip "Bearer "

        try:
            # Validate token via Supabase API — no JWT secret needed
            supabase = _get_supabase()
            response = supabase.auth.get_user(token)
            user = response.user
            if user is None:
                return jsonify({"error": "Invalid token"}), 401
        except Exception:
            return jsonify({"error": "Invalid token"}), 401

        # auth.users.id from validated token
        g.user_id = user.id
        g.user_email = user.email or ""

        # Resolve profile_id (profiles.id) — all data tables reference this, not auth.users.id
        client = get_pg()

        profile_res = (
            client.from_("profiles")
            .select("id")
            .eq("auth_id", g.user_id)
            .execute()
        )
        g.profile_id = profile_res.data[0]["id"] if profile_res.data else None

        # Resolve family_id for Phase 2
        family_res = (
            client.from_("family_members")
            .select("family_id")
            .eq("user_id", g.user_id)
            .execute()
        )
        g.family_id = family_res.data[0]["family_id"] if family_res.data else None

        return f(*args, **kwargs)

    return decorated

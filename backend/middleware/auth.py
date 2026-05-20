import os
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


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing auth token"}), 401

        token = auth_header[7:]

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

import os
import jwt as pyjwt
from functools import wraps
from flask import request, jsonify, g
from service.database import get_pg

# Module-level caches — avoids per-request DB lookups for data that never changes
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
            jwt_secret = os.environ.get("SUPABASE_JWT_SECRET")
            payload = pyjwt.decode(
                token,
                jwt_secret,
                algorithms=["HS256"],
                audience="authenticated",
            )
            user_id = payload["sub"]
            user_email = payload.get("email", "")
        except pyjwt.ExpiredSignatureError:
            return jsonify({"error": "Token expired"}), 401
        except Exception:
            return jsonify({"error": "Invalid token"}), 401

        g.user_id = user_id
        g.user_email = user_email

        client = get_pg()

        if user_id not in _profile_cache:
            profile_res = (
                client.from_("profiles")
                .select("id")
                .eq("auth_id", user_id)
                .execute()
            )
            _profile_cache[user_id] = profile_res.data[0]["id"] if profile_res.data else None

        if user_id not in _family_cache:
            family_res = (
                client.from_("family_members")
                .select("family_id")
                .eq("user_id", user_id)
                .execute()
            )
            _family_cache[user_id] = family_res.data[0]["family_id"] if family_res.data else None

        g.profile_id = _profile_cache[user_id]
        g.family_id = _family_cache[user_id]

        return f(*args, **kwargs)

    return decorated

import os
from dotenv import load_dotenv
from postgrest import SyncPostgrestClient

# Load environment variables from .env file
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env'))

def get_pg():
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    
    if not url or not key:
        raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in .env file")

    # Ensure URL ends with /rest/v1
    base_url = url.rstrip("/") + "/rest/v1"
    
    return SyncPostgrestClient(base_url, headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
    })

from service.database import get_pg
from dateutil.parser import parse

def fetch_earnings_for_period(month, year, user_id=None, family_id=None):
    client = get_pg()

    start_date = f"{year}-{month:02d}-01"
    if month == 12:
        end_date = f"{year + 1}-01-01"
    else:
        end_date = f"{year}-{month + 1:02d}-01"

    query = client.from_("earnings")\
        .select("*, profiles(name)")\
        .gte("earned_at", start_date)\
        .lt("earned_at", end_date)

    if family_id:
        query = query.eq("family_id", family_id)
    elif user_id:
        query = query.eq("user_id", user_id)
        
    res = query.execute()
    data = res.data
    
    # Process if needed, e.g., flatten structure
    filtered = []
    for item in data:
        flat = item.copy()
        flat['user_name'] = item['profiles']['name'] if item.get('profiles') else 'Unknown'
        filtered.append(flat)
        
    return filtered

def add_earning(user_id, amount, description, earned_at):
    client = get_pg()
    data = {
        "user_id": user_id,
        "amount": amount,
        "description": description,
        "earned_at": earned_at
    }
    res = client.from_("earnings").insert(data).execute()
    return res.data

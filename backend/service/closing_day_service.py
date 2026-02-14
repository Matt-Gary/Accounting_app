from service.database import get_pg

def get_closing_day_for_month(month: int, year: int) -> int | None:
    """
    Get the closing day override for a specific month/year.
    Returns None if no override exists.
    """
    client = get_pg()
    res = client.from_("closing_day_overrides").select("closing_day").eq("month", month).eq("year", year).execute()
    
    if res.data and len(res.data) > 0:
        return res.data[0]['closing_day']
    return None


def set_closing_day_for_month(month: int, year: int, closing_day: int) -> dict:
    """
    Set (upsert) the closing day override for a specific month/year.
    """
    client = get_pg()
    
    # Try to update first
    existing = client.from_("closing_day_overrides").select("id").eq("month", month).eq("year", year).execute()
    
    if existing.data and len(existing.data) > 0:
        # Update existing
        res = client.from_("closing_day_overrides").update({
            "closing_day": closing_day,
            "updated_at": "NOW()"
        }).eq("month", month).eq("year", year).execute()
    else:
        # Insert new
        res = client.from_("closing_day_overrides").insert({
            "month": month,
            "year": year,
            "closing_day": closing_day
        }).execute()
    
    return res.data[0] if res.data else {}


def delete_closing_day_for_month(month: int, year: int) -> bool:
    """
    Delete the closing day override for a specific month/year.
    Returns True if deleted, False if not found.
    """
    client = get_pg()
    res = client.from_("closing_day_overrides").delete().eq("month", month).eq("year", year).execute()
    return len(res.data) > 0 if res.data else False

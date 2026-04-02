
import sys
import os
from datetime import date
import time

# Add current directory to path
sys.path.append(os.getcwd())

from service.database import get_pg
from app import materialize_recurring_expenses

def test_duplication_bug():
    print("--- Starting Reproduction Test ---")
    client = get_pg()
    
    # Fetch real users
    users = client.from_("profiles").select("id").limit(2).execute().data
    if len(users) < 2:
        print("Need at least 2 users in profiles table to test.")
        # Try to use same user if only 1, but might not trigger duplication if filtering is by user
        # But if I change user to SAME user, it won't duplicate.
        # I'll try to insert a fake user if possible, or just fail.
        if len(users) == 0:
             print("No users found.")
             return
        user_a = users[0]['id']
        user_b = users[0]['id'] # Fallback, but test won't be perfect
    else:
        user_a = users[0]['id']
        user_b = users[1]['id']

    # Fetch valid payment method
    pms = client.from_("payment_methods").select("id").limit(1).execute().data
    if not pms:
        print("No payment methods found.")
        return
    pm_id = pms[0]['id']

    # Fetch valid category
    cats = client.from_("categories").select("*").limit(1).execute().data
    if not cats:
        print("No categories found.")
        return
    cat_key = cats[0]['key']
    
    # Cleanup previous test run
    print("Cleaning up...")
    client.from_("expenses").delete().eq("comment", "TEST_RECURRING").execute()
    client.from_("recurring_expenses").delete().eq("description", "TEST_RECURRING").execute()
    
    print(f"Creating recurring expense for User A ({user_a})...")
    rec_data = {
        "user_id": user_a,
        "amount": 100,
        "category_key": cat_key,
        "payment_method_id": pm_id,
        "day_of_month": date.today().day,
        "description": "TEST_RECURRING",
        "active": True
    }
    
    res = client.from_("recurring_expenses").insert(rec_data).execute()
    if not res.data:
        print("Failed to create recurring expense")
        return
    
    rid = res.data[0]['id']
    print(f"Recurring ID: {rid}")
    
    # 2. Materialize for User A
    print("Materializing for User A...")
    materialize_recurring_expenses(date.today().month, date.today().year, user_a)
    
    # Check expense
    exps = client.from_("expenses").select("*").eq("recurring_id", rid).execute().data
    print(f"Expenses for Rid {rid}: {len(exps)}")
    if len(exps) != 1:
        print("ERROR: Should have 1 expense")
        return
    print(f"Expense User: {exps[0]['user_id']}")
    
    # 3. Update Recurring to User B logic (Simulating API call logic locally)
    print("Updating Recurring to User B...")
    
    # Simulate the logic I added to app.py
    # NOTE: I am calling the API endpoint logic here manually or I could curl the running app.
    # Let's try to verify if the 'update' returns data first.
    
    update_data = {"user_id": user_b}
    res_update = client.from_("recurring_expenses").update(update_data).eq("id", rid).execute()
    print(f"Update Result Data: {res_update.data}") 
    
    updated_recurring = res_update.data[0] if res_update.data else None
    
    if updated_recurring:
        print("Logic would trigger propagation.")
        # ... logic ...
    else:
        print("Logic would NOT trigger propagation (res.data is empty).")
        
    # If I manually run the propagation logic here to verify it WORKS if triggered:
    if updated_recurring:
        today = date.today()
        first_of_month = date(today.year, today.month, 1)
        client.from_("expenses")\
             .update({"user_id": user_b})\
             .eq("recurring_id", rid)\
             .gte("spent_at", first_of_month.isoformat())\
             .execute()
             
    # 4. Check Expenses again
    exps_after = client.from_("expenses").select("*").eq("recurring_id", rid).execute().data
    print(f"Expenses Match User B? {exps_after[0]['user_id'] == user_b}")
    
    # 5. Materialize for User B (Simulate Dashboard load)
    print("Materializing for User B...")
    materialize_recurring_expenses(date.today().month, date.today().year, user_b)
    
    # 6. Check for duplicates
    final_exps = client.from_("expenses").select("*").eq("recurring_id", rid).execute().data
    print(f"Final Count of Expenses: {len(final_exps)}")
    for e in final_exps:
        print(f" - Exp ID: {e['id']}, User: {e['user_id']}")

    if len(final_exps) > 1:
        print("BUG REPRODUCED: Duplicates found.")
    else:
        print("SUCCESS: No duplicates.")
        
    # Cleanup
    # client.from_("expenses").delete().eq("comment", "TEST_RECURRING").execute()
    # client.from_("recurring_expenses").delete().eq("description", "TEST_RECURRING").execute()

if __name__ == "__main__":
    test_duplication_bug()

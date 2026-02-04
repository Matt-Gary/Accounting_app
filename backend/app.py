from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from service.database import get_pg
from service.billing_service import get_billing_period, get_query_range_for_month
import pandas as pd
import io
import os
from dateutil.parser import parse

app = Flask(__name__)
CORS(app) # Enable CORS for all routes

# Payment Methods Cache (Simplified for demo, locally cached or fetched per request)
# Ideally, fetch from DB.
def get_payment_methods():
    client = get_pg()
    res = client.from_("payment_methods").select("*").execute()
    # Return dict mapping id -> method
    return {pm['id']: pm for pm in res.data}

from service.earnings_service import fetch_earnings_for_period, add_earning
from service.investment_service import fetch_portfolio, add_investment, update_investment, delete_investment, get_portfolio_distribution_by_type
from datetime import timedelta, date

# ============= RECURRING EXPENSES LOGIC =============

def materialize_recurring_expenses(month, year, user_id):
    """
    Auto-generates expense records for active recurring definitions.
    Only creates expenses for months on or after the template creation month.
    """
    client = get_pg()
    
    # Get all active recurring expenses for this user
    recurring_defs = client.from_("recurring_expenses")\
        .select("*")\
        .eq("user_id", user_id)\
        .eq("active", True)\
        .execute().data
        
    if not recurring_defs:
        return
    
    # Get existing materialized expenses for this period to avoid duplicates
    start_date, end_date = get_query_range_for_month(month, year)
    query_end = end_date + timedelta(days=1)
    
    existing_expenses = client.from_("expenses")\
        .select("id, recurring_id, spent_at")\
        .eq("user_id", user_id)\
        .not_.is_("recurring_id", "null")\
        .gte("spent_at", start_date.isoformat())\
        .lt("spent_at", query_end.isoformat())\
        .execute().data
    
    # Map recurring_id -> list of spent_at dates already created
    created_map = {}
    for exp in existing_expenses:
        rid = exp['recurring_id']
        if rid not in created_map:
            created_map[rid] = []
        created_map[rid].append(parse(exp['spent_at']).date())
    
    # Process each recurring definition
    for rdef in recurring_defs:
        rid = rdef['id']
        day = rdef['day_of_month'] or 1
        
        print(f"[DEBUG] Processing recurring '{rdef.get('description')}' (id={rid}, day={day}) for {month}/{year}")

        # Calculate target date, handling end-of-month edge cases
        try:
            target_date = date(year, month, day)
        except ValueError:
            # Handle cases like Feb 31 -> Feb 28/29
            import calendar
            last_day = calendar.monthrange(year, month)[1]
            target_date = date(year, month, min(day, last_day))
        
        print(f"[DEBUG] Target date: {target_date}")

        # Don't backdate: only allow expenses within 1 day of creation (timezone buffer)
        # If created Feb 1st, we allow Jan 31st (for UTC offsets) but not Jan 1st.
        created_at_date = parse(rdef['created_at']).date()
        print(f"[DEBUG] Created at: {created_at_date}")
        
        # Calculate strict cutoff: target must be >= created_at - 1 day
        cutoff_slop = timedelta(days=1)
        if target_date < (created_at_date - cutoff_slop):
            print(f"[DEBUG] SKIPPING: Target {target_date} is before creation {created_at_date} (minus buffer)")
            continue
        
        # Check if already materialized for this month
        already_created = False
        if rid in created_map:
            for dt in created_map[rid]:
                # We check strict month match for materialization to avoid duplicates in same month
                if dt.month == month and dt.year == year:
                    already_created = True
                    print(f"[DEBUG] SKIPPING: Already created for this month on {dt}")
                    break
        
        if not already_created:
            print(f"[DEBUG] MATERIALIZING: Creating expense for {target_date}")
            # Create the expense
            new_exp = {
                "user_id": user_id,
                "amount": rdef['amount'],
                "category_key": rdef['category_key'],
                "payment_method_id": rdef['payment_method_id'],
                # "description": rdef['description'], # expenses table doesn't have description, likely uses comment
                "spent_at": target_date.isoformat(),
                "recurring_id": rid,
                "comment": f"Recurring: {rdef['description'] or ''}".strip()
            }
            client.from_("expenses").insert(new_exp).execute()

# =====================================================

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

# ... (Expenses Logic Omitted for brevity in search, but preserved in file via correct ranges) ...
# Actually, I need to match the replacement properly.
# The user wants to APPEND standard CRUD routes. I'll put them before the report route or at the end.

# INVESTMENTS ENDPOINTS
@app.route('/investments', methods=['GET'])
def get_investments():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    
    try:
        portfolio = fetch_portfolio(user_id)
        return jsonify(portfolio)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/investments', methods=['POST'])
def create_investment():
    data = request.json
    required_fields = ['user_id', 'type', 'name', 'quantity']
    for field in required_fields:
        if field not in data:
            return jsonify({"error": f"Missing field: {field}"}), 400
            
    try:
        res = add_investment(data['user_id'], data)
        return jsonify(res), 201
    except Exception as e:
         return jsonify({"error": str(e)}), 500

@app.route('/investments/<inv_id>', methods=['PUT'])
def edit_investment(inv_id):
    data = request.json
    user_id = request.args.get('user_id') or data.get('user_id')
    if not user_id:
         return jsonify({"error": "user_id is required"}), 400
         
    try:
        # Filter allowed fields
        allowed = ['quantity', 'cost_basis', 'name', 'symbol', 'type']
        updates = {k: v for k, v in data.items() if k in allowed}
        
        res = update_investment(inv_id, user_id, updates)
        return jsonify(res)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/investments/<inv_id>', methods=['DELETE'])
def remove_investment(inv_id):
    user_id = request.args.get('user_id')
    if not user_id:
         return jsonify({"error": "user_id is required"}), 400
         
    try:
        res = delete_investment(inv_id, user_id)
        return jsonify(res)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/investments/distribution', methods=['GET'])
def get_distribution():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    
    # Optional filter: investment_types as comma-separated string
    # Example: ?investment_types=stock,crypto
    types_param = request.args.get('investment_types')
    investment_types = None
    if types_param:
        investment_types = [t.strip() for t in types_param.split(',') if t.strip()]
    
    try:
        distribution = get_portfolio_distribution_by_type(user_id, investment_types)
        return jsonify(distribution)
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# Helper function to fetch and filter expenses
def fetch_expenses_for_period(month, year, user_id=None):
    start_date, end_date = get_query_range_for_month(month, year)
    
    # Fix: Use .lt() with the start of the next day to include the entire end_date
    # This prevents excluding expenses on the last day of the month due to timestamp comparison
    query_end = end_date + timedelta(days=1)
    
    client = get_pg()
    # We need to fetch profiles(name) as well
    query = client.from_("expenses")\
        .select("*, categories(label), payment_methods(name, is_credit_card, closing_day), profiles(name)")\
        .gte("spent_at", start_date.isoformat())\
        .lt("spent_at", query_end.isoformat())
        
    if user_id:
        # Auto-materialize for this specific user before fetching
        materialize_recurring_expenses(month, year, user_id)
        query = query.eq("user_id", user_id)
    else:
        # No user filter - materialize for ALL users
        try:
            all_users = client.from_("profiles").select("id").execute().data
            for user in all_users:
                materialize_recurring_expenses(month, year, user['id'])
        except Exception as e:
            print(f"Error materializing for all users: {e}")
        
    res = query.execute()
    raw_expenses = res.data
    
    filtered = []
    for exp in raw_expenses:
        spent_at_date = parse(exp['spent_at']).date()
        pm_info = exp['payment_methods']
        closing_day = pm_info.get('closing_day', 23) or 23 
        
        b_month, b_year = get_billing_period(
            spent_at_date, 
            pm_info['is_credit_card'], 
            closing_day
        )
        
        if b_month == month and b_year == year:
            # Flatten for report
            flat_exp = exp.copy()
            flat_exp['category_label'] = exp['categories']['label']
            flat_exp['payment_method_name'] = pm_info['name']
            flat_exp['user_name'] = exp['profiles']['name'] # Add User Name
            filtered.append(flat_exp)
            
    return filtered

@app.route('/dashboard', methods=['GET'])
def dashboard():
    try:
        month = int(request.args.get('month'))
        year = int(request.args.get('year'))
    except (TypeError, ValueError):
        return jsonify({"error": "Missing or invalid month/year"}), 400
        
    user_id = request.args.get('user_id')
    expenses = fetch_expenses_for_period(month, year, user_id)
    earnings = fetch_earnings_for_period(month, year, user_id)
    
    total_spent = sum(float(e['amount']) for e in expenses)
    total_earned = sum(float(e['amount']) for e in earnings)
    
    category_totals = {}
    user_spend_totals = {}
    user_earned_totals = {}

    for e in expenses:
        amt = float(e['amount'])
        # Category Breakdown
        lbl = e['category_label']
        category_totals[lbl] = category_totals.get(lbl, 0.0) + amt
        # User Breakdown
        u_name = e['user_name']
        user_spend_totals[u_name] = user_spend_totals.get(u_name, 0.0) + amt
            
    for e in earnings:
        amt = float(e['amount'])
        u_name = e['user_name']
        user_earned_totals[u_name] = user_earned_totals.get(u_name, 0.0) + amt

    return jsonify({
        "billing_period": f"{month}/{year}",
        "total_spent": total_spent,
        "total_earned": total_earned,
        "category_breakdown": category_totals,
        "user_spend_breakdown": user_spend_totals,
        "user_earned_breakdown": user_earned_totals,
        "expense_count": len(expenses),
        "expenses": expenses,
        "earning_count": len(earnings),
        "earnings": earnings
    })

@app.route('/earnings', methods=['POST'])
def create_earning():
    data = request.json
    required_fields = ['user_id', 'amount', 'earned_at']
    for field in required_fields:
        if field not in data:
            return jsonify({"error": f"Missing field: {field}"}), 400
            
    try:
        new_earning = add_earning(
            data['user_id'],
            data['amount'],
            data.get('description'),
            data['earned_at']
        )
        return jsonify(new_earning), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/expenses/<expense_id>', methods=['DELETE'])
def delete_expense(expense_id):
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    
    try:
        client = get_pg()
        # Verify ownership before deletion
        res = client.from_("expenses").delete().eq("id", expense_id).eq("user_id", user_id).execute()
        return jsonify({"message": "Expense deleted successfully"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# RECURRING EXPENSES ENDPOINTS

@app.route('/recurring-expenses', methods=['GET'])
def list_recurring():
    # Optional filtering by user_id
    user_id = request.args.get('user_id')
    try:
        client = get_pg()
        query = client.from_("recurring_expenses").select("*, categories(label), payment_methods(name)")
        if user_id:
            query = query.eq("user_id", user_id)
        res = query.execute()
        return jsonify(res.data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/recurring-expenses', methods=['POST'])
def create_recurring():
    data = request.json
    required = ['user_id', 'amount', 'category_key', 'payment_method_id', 'day_of_month']
    for f in required:
        if f not in data:
            return jsonify({"error": f"Missing field: {f}"}), 400
    try:
        client = get_pg()
        # Add created_at explicitly (though DB defaults to Now)? DB default is fine.
        res = client.from_("recurring_expenses").insert(data).execute()
        return jsonify(res.data[0]), 201
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/recurring-expenses/<rid>', methods=['PUT'])
def update_recurring(rid):
    data = request.json
    print(f"[DEBUG] UPDATE RECURRING id={rid} data={data}")
    # We allow updating without user_id validation since no strict auth
    try:
        client = get_pg()
        # Specific updates like 'active', 'amount', etc.
        # Chain .select() to ensure we get the updated record back
        res = client.from_("recurring_expenses").update(data).eq("id", rid).select().execute()
        updated_recurring = res.data[0] if res.data else None
        
        print(f"[DEBUG] UPDATED RECURRING RESULT: {updated_recurring}")

        if updated_recurring:
            # Propagate changes to future expenses (from start of current month)
            today = date.today()
            first_of_month = date(today.year, today.month, 1)
            print(f"[DEBUG] Propagating changes from {first_of_month}")

            # Build update payload for expenses
            expense_updates = {}
            if 'user_id' in data:
                expense_updates['user_id'] = data['user_id']
            if 'amount' in data:
                expense_updates['amount'] = data['amount']
            if 'category_key' in data:
                 expense_updates['category_key'] = data['category_key']
            if 'payment_method_id' in data:
                 expense_updates['payment_method_id'] = data['payment_method_id']
            if 'description' in data:
                 expense_updates['comment'] = f"Recurring: {data['description']}"

            print(f"[DEBUG] Expense Updates payload: {expense_updates}")
            
            if expense_updates:
                 # Check what we are targeting
                 target_check = client.from_("expenses")\
                     .select("id, spent_at")\
                     .eq("recurring_id", rid)\
                     .gte("spent_at", first_of_month.isoformat())\
                     .execute()
                 print(f"[DEBUG] Target expenses found: {len(target_check.data) if target_check.data else 0}")
                 
                 update_res = client.from_("expenses")\
                     .update(expense_updates)\
                     .eq("recurring_id", rid)\
                     .gte("spent_at", first_of_month.isoformat())\
                     .select("id")\
                     .execute()
                 print(f"[DEBUG] Expenses update executed. Updated count: {len(update_res.data) if update_res.data else 0}")
        else:
             print("[WARN] Update succeeded but returned no data? Check if ID exists or RLS.")

        return jsonify(updated_recurring if updated_recurring else {}), 200
    except Exception as e:
        print(f"[ERROR] Update recurring failed: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/recurring-expenses/<rid>', methods=['DELETE'])
def delete_recurring(rid):
    try:
        client = get_pg()
        print(f"[DEBUG] DELETING RECURRING id={rid}")
        
        # First, check how many expenses are linked to this recurring
        check_res = client.from_("expenses")\
            .select("id", count="exact")\
            .eq("recurring_id", rid)\
            .execute()
        print(f"[DEBUG] Found {check_res.count if hasattr(check_res, 'count') else 'unknown'} linked expenses")
        
        today = date.today()
        first_of_month = date(today.year, today.month, 1)
        
        # 1. Delete future materialized expenses (from start of current month)
        print("[DEBUG] Deleting future expenses...")
        res_del = client.from_("expenses")\
            .delete()\
            .eq("recurring_id", rid)\
            .gte("spent_at", first_of_month.isoformat())\
            .execute()
        print(f"[DEBUG] Delete response: {res_del}")

        # 2. Unlink ANY remaining expenses - MUST use .select() to make update return data
        print("[DEBUG] Unlinking remaining expenses...")
        res_unlink = client.from_("expenses")\
            .update({"recurring_id": None})\
            .eq("recurring_id", rid)\
            .select("id")\
            .execute()
        print(f"[DEBUG] Unlinked {len(res_unlink.data) if res_unlink.data else 0} remaining expenses")
        print(f"[DEBUG] Unlink response: {res_unlink}")

        # 3. Verify no expenses are still linked
        verify_res = client.from_("expenses")\
            .select("id", count="exact")\
            .eq("recurring_id", rid)\
            .execute()
        remaining_count = verify_res.count if hasattr(verify_res, 'count') else len(verify_res.data) if verify_res.data else 0
        print(f"[DEBUG] Remaining linked expenses: {remaining_count}")
        
        if remaining_count > 0:
            print(f"[ERROR] Still have {remaining_count} expenses linked after unlink attempt!")
            return jsonify({"error": f"Cannot delete: {remaining_count} expenses still linked"}), 400

        # 4. Delete the recurring definition
        print("[DEBUG] Deleting recurring definition...")
        client.from_("recurring_expenses").delete().eq("id", rid).execute()
        print("[DEBUG] Successfully deleted recurring definition")
        return jsonify({"message": "Deleted"}), 200
    except Exception as e:
        print(f"[ERROR] Delete recurring failed: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/report/monthly', methods=['GET'])
def monthly_report():
    """
    Export monthly report as Excel.
    """
    try:
        month = int(request.args.get('month'))
        year = int(request.args.get('year'))
    except (TypeError, ValueError):
        return jsonify({"error": "Missing or invalid month/year"}), 400
        
    user_id = request.args.get('user_id')
    expenses = fetch_expenses_for_period(month, year, user_id)
    earnings = fetch_earnings_for_period(month, year, user_id)
    
    # Calculate totals
    total_spent = sum(float(e['amount']) for e in expenses)
    total_earned = sum(float(e['amount']) for e in earnings)
    balance = total_earned - total_spent
    
    # Create DataFrames
    df_exp = pd.DataFrame(expenses)
    df_earn = pd.DataFrame(earnings)
    
    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
        workbook = writer.book
        
        # Create Summary Sheet (first sheet)
        summary_sheet = workbook.add_worksheet('Summary')
        
        # Formats
        header_format = workbook.add_format({
            'bold': True,
            'font_size': 14,
            'bg_color': '#4472C4',
            'font_color': 'white',
            'align': 'center'
        })
        title_format = workbook.add_format({
            'bold': True,
            'font_size': 12,
            'bg_color': '#D9E1F2'
        })
        currency_format = workbook.add_format({'num_format': 'R$ #,##0.00'})
        positive_format = workbook.add_format({
            'num_format': 'R$ #,##0.00',
            'font_color': '#006100',
            'bold': True
        })
        negative_format = workbook.add_format({
            'num_format': 'R$ #,##0.00',
            'font_color': '#9C0006',
            'bold': True
        })
        
        # Write Summary Header
        summary_sheet.merge_range('A1:B1', f'Monthly Report - {month}/{year}', header_format)
        
        # Overall Summary
        row = 2
        summary_sheet.write(row, 0, 'Total Earnings', title_format)
        summary_sheet.write(row, 1, total_earned, positive_format)
        row += 1
        summary_sheet.write(row, 0, 'Total Spending', title_format)
        summary_sheet.write(row, 1, total_spent, negative_format)
        row += 1
        summary_sheet.write(row, 0, 'Balance', title_format)
        balance_format = positive_format if balance >= 0 else negative_format
        summary_sheet.write(row, 1, balance, balance_format)
        
        # Category Breakdown
        if not df_exp.empty and 'category_label' in df_exp.columns:
            row += 2
            summary_sheet.merge_range(row, 0, row, 1, 'Spending by Category', header_format)
            row += 1
            category_totals = df_exp.groupby('category_label')['amount'].sum().sort_values(ascending=False)
            for category, amount in category_totals.items():
                summary_sheet.write(row, 0, category)
                summary_sheet.write(row, 1, float(amount), currency_format)
                row += 1
        
        # User Breakdown
        if not df_exp.empty and 'user_name' in df_exp.columns:
            row += 1
            summary_sheet.merge_range(row, 0, row, 1, 'Spending by User', header_format)
            row += 1
            user_totals = df_exp.groupby('user_name')['amount'].sum().sort_values(ascending=False)
            for user, amount in user_totals.items():
                summary_sheet.write(row, 0, user)
                summary_sheet.write(row, 1, float(amount), currency_format)
                row += 1
        
        # Earnings by User
        if not df_earn.empty and 'user_name' in df_earn.columns:
            row += 1
            summary_sheet.merge_range(row, 0, row, 1, 'Earnings by User', header_format)
            row += 1
            user_earnings = df_earn.groupby('user_name')['amount'].sum().sort_values(ascending=False)
            for user, amount in user_earnings.items():
                summary_sheet.write(row, 0, user)
                summary_sheet.write(row, 1, float(amount), currency_format)
                row += 1
        
        # Set column widths
        summary_sheet.set_column('A:A', 25)
        summary_sheet.set_column('B:B', 15)
        
        # Expenses Sheet
        if not df_exp.empty:
            cols_to_keep = ['spent_at', 'amount', 'category_label', 'payment_method_name', 'user_name', 'comment', 'currency', 'installments']
            # Ensure columns exist before selecting
            existing_cols = [c for c in cols_to_keep if c in df_exp.columns]
            df_exp_export = df_exp[existing_cols].copy()
            df_exp_export.to_excel(writer, sheet_name='Expenses', index=False)
            
            # Format expenses sheet
            expense_sheet = writer.sheets['Expenses']
            expense_sheet.set_column('A:A', 20)  # Date
            expense_sheet.set_column('B:B', 12)  # Amount
            expense_sheet.set_column('C:C', 20)  # Category
            expense_sheet.set_column('D:D', 20)  # Payment Method
            expense_sheet.set_column('E:E', 15)  # User
            expense_sheet.set_column('F:F', 30)  # Comment

        # Earnings Sheet
        if not df_earn.empty:
            cols_earn = ['earned_at', 'amount', 'description', 'user_name']
            existing_cols_earn = [c for c in cols_earn if c in df_earn.columns]
            df_earn_export = df_earn[existing_cols_earn].copy()
            df_earn_export.to_excel(writer, sheet_name='Earnings', index=False)
            
            # Format earnings sheet
            earnings_sheet = writer.sheets['Earnings']
            earnings_sheet.set_column('A:A', 20)  # Date
            earnings_sheet.set_column('B:B', 12)  # Amount
            earnings_sheet.set_column('C:C', 30)  # Description
            earnings_sheet.set_column('D:D', 15)  # User

    output.seek(0)
    
    filename = f"report_{month}_{year}.xlsx"
    return send_file(
        output, 
        mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        as_attachment=True,
        download_name=filename
    )

if __name__ == '__main__':
    app.run(debug=True, port=int(os.environ.get("PORT", 5000)))

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
from service.investment_service import fetch_portfolio, add_investment, update_investment, delete_investment

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


# Helper function to fetch and filter expenses
def fetch_expenses_for_period(month, year, user_id=None):
    start_date, end_date = get_query_range_for_month(month, year)
    
    client = get_pg()
    # We need to fetch profiles(name) as well
    query = client.from_("expenses")\
        .select("*, categories(label), payment_methods(name, is_credit_card, closing_day), profiles(name)")\
        .gte("spent_at", start_date.isoformat())\
        .lte("spent_at", end_date.isoformat())
        
    if user_id:
        query = query.eq("user_id", user_id)
        
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
    
    # Create DataFrames
    df_exp = pd.DataFrame(expenses)
    df_earn = pd.DataFrame(earnings)
    
    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
        if not df_exp.empty:
            cols_to_keep = ['spent_at', 'amount', 'category_label', 'payment_method_name', 'comment', 'currency']
            # Ensure columns exist before selecting
            existing_cols = [c for c in cols_to_keep if c in df_exp.columns]
            df_exp = df_exp[existing_cols]
            df_exp.to_excel(writer, sheet_name='Expenses', index=False)
            
            summary = df_exp.groupby('category_label')['amount'].sum().reset_index() if 'category_label' in df_exp.columns else pd.DataFrame()
            summary.to_excel(writer, sheet_name='Exp_Summary', index=False)

        if not df_earn.empty:
            cols_earn = ['earned_at', 'amount', 'description', 'user_name']
            existing_cols_earn = [c for c in cols_earn if c in df_earn.columns]
            df_earn = df_earn[existing_cols_earn]
            df_earn.to_excel(writer, sheet_name='Earnings', index=False)

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

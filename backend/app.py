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

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

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
    
    total_amount = sum(float(e['amount']) for e in expenses)
    category_totals = {}
    user_totals = {} # New Breakdown

    for e in expenses:
        amt = float(e['amount'])
        
        # Category Breakdown
        lbl = e['category_label']
        category_totals[lbl] = category_totals.get(lbl, 0.0) + amt
        
        # User Breakdown
        u_name = e['user_name']
        user_totals[u_name] = user_totals.get(u_name, 0.0) + amt
            
    return jsonify({
        "billing_period": f"{month}/{year}",
        "total_spent": total_amount,
        "category_breakdown": category_totals,
        "user_breakdown": user_totals, # Return new data
        "expense_count": len(expenses),
        "expenses": expenses
    })

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
    
    if not expenses:
        return jsonify({"message": "No expenses found for this period"}), 404
        
    # Create DataFrame
    df = pd.DataFrame(expenses)
    # Select and rename columns
    cols_to_keep = ['spent_at', 'amount', 'category_label', 'payment_method_name', 'comment', 'currency']
    df = df[cols_to_keep]
    df.rename(columns={
        'spent_at': 'Date',
        'amount': 'Amount',
        'category_label': 'Category',
        'payment_method_name': 'Method',
        'comment': 'Comment',
        'currency': 'Currency'
    }, inplace=True)
    
    # Generate Excel
    output = io.BytesIO()
    with pd.ExcelWriter(output, engine='xlsxwriter') as writer:
        df.to_excel(writer, sheet_name='Expenses', index=False)
        # Create a summary sheet?
        summary = df.groupby('Category')['Amount'].sum().reset_index()
        summary.to_excel(writer, sheet_name='Summary', index=False)
        
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

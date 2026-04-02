import yfinance as yf
from service.database import get_pg

def fetch_portfolio(user_id):
    client = get_pg()
    
    # 1. Fetch investments from DB
    res = client.from_("investments").select("*").eq("user_id", user_id).execute()
    investments = res.data
    
    if not investments:
        return {"total_value": 0.0, "investments": []}

    # 2. Collect symbols to fetch (Stocks/Crypto) plus Exchange Rates
    symbols = [inv['symbol'] for inv in investments if inv['type'] in ('stock', 'crypto') and inv['symbol']]
    
    # Exchange Rates needed:
    # BRL=X -> USD to BRL (e.g. 5.15)
    # EURUSD=X -> EUR to USD (e.g. 1.05)
    # USDPLN=X -> USD to PLN (e.g. 3.95)
    rates_map = {
        'BRL': 'BRL=X',
        'EUR': 'EURUSD=X',
        'PLN': 'USDPLN=X'
    }
    
    for r in rates_map.values():
        symbols.append(r)
    
    # 3. Fetch current prices
    prices = {}
    if symbols:
        tickers_str = " ".join(set(symbols)) # Unique
        try:
            data = yf.Tickers(tickers_str)
            for sym in set(symbols):
                try:
                    ticker = data.tickers[sym]
                    # Try fast_info first, then history
                    price = 0.0
                    if hasattr(ticker, 'fast_info'):
                        # safe access
                        try:
                            price = ticker.fast_info['last_price']
                        except:
                            pass
                    
                    if price == 0.0:
                        hist = ticker.history(period="1d")
                        if not hist.empty:
                            price = hist['Close'].iloc[-1]
                            
                    prices[sym] = price
                except Exception as e:
                    print(f"Error fetching {sym}: {e}")
                    prices[sym] = 0.0
        except Exception as e:
            print(f"Batch fetch error: {e}")

    # Extract Rates
    usd_to_brl = prices.get(rates_map['BRL'], 5.0) 
    eur_to_usd = prices.get(rates_map['EUR'], 1.0)
    usd_to_pln = prices.get(rates_map['PLN'], 4.0)

    # Sanity checks and fallback logging
    if usd_to_brl <= 0.1:
        print(f"[WARNING] Invalid USD/BRL rate ({usd_to_brl}), using fallback: 5.0")
        usd_to_brl = 5.0
    elif rates_map['BRL'] not in prices or prices.get(rates_map['BRL'], 0) == 5.0:
        print(f"[WARNING] Failed to fetch USD/BRL rate from Yahoo Finance, using fallback: 5.0")
    
    if eur_to_usd <= 0.1:
        print(f"[WARNING] Invalid EUR/USD rate ({eur_to_usd}), using fallback: 1.0")
        eur_to_usd = 1.0
    elif rates_map['EUR'] not in prices or prices.get(rates_map['EUR'], 0) == 1.0:
        print(f"[WARNING] Failed to fetch EUR/USD rate from Yahoo Finance, using fallback: 1.0")
    
    if usd_to_pln <= 0.1:
        print(f"[WARNING] Invalid USD/PLN rate ({usd_to_pln}), using fallback: 4.0")
        usd_to_pln = 4.0
    elif rates_map['PLN'] not in prices or prices.get(rates_map['PLN'], 0) == 4.0:
        print(f"[WARNING] Failed to fetch USD/PLN rate from Yahoo Finance, using fallback: 4.0")

    # 4. Calculate Values
    total_val_usd = 0.0
    total_val_brl = 0.0
    enriched_investments = []
    
    for inv in investments:
        itype = inv['type']
        qty = float(inv['quantity'])
        inv_currency = inv.get('currency', 'BRL') # Default BRL
        
        current_price = 0.0
        
        if itype == 'cash':
            current_price = 1.0
            val_in_native = qty
        elif itype in ('stock', 'crypto') and inv['symbol']:
            current_price = prices.get(inv['symbol'], 0.0)
            val_in_native = qty * current_price
        else:
            # Bonds / Other
            val_in_native = qty # Assuming qty holds value
        
        # Convert Native -> USD
        if inv_currency == 'USD':
            val_usd = val_in_native
        elif inv_currency == 'BRL':
            val_usd = val_in_native / usd_to_brl
        elif inv_currency == 'EUR':
            val_usd = val_in_native * eur_to_usd
        elif inv_currency == 'PLN':
            val_usd = val_in_native / usd_to_pln
        else:
            val_usd = val_in_native # Fallback
            
        # Convert USD -> BRL
        val_brl = val_usd * usd_to_brl

        # PnL (Native Currency)
        cost_basis = float(inv.get('cost_basis') or 0.0)
        pnl = val_in_native - cost_basis
        pnl_pct = (pnl / cost_basis * 100) if cost_basis > 0 else 0.0
        
        inv['current_price'] = current_price
        inv['current_value_native'] = val_in_native
        inv['current_value_usd'] = val_usd
        inv['current_value_brl'] = val_brl
        inv['pnl'] = pnl
        inv['pnl_pct'] = pnl_pct
        
        total_val_usd += val_usd
        total_val_brl += val_brl
        enriched_investments.append(inv)
        
    return {
        "total_value_usd": total_val_usd,
        "total_value_brl": total_val_brl,
        "exchange_rate_usd_brl": usd_to_brl,
        "exchange_rate_eur_usd": eur_to_usd,
        "exchange_rate_usd_pln": usd_to_pln,
        "investments": enriched_investments
    }

def add_investment(user_id, data):
    client = get_pg()
    payload = {
        "user_id": user_id,
        "type": data['type'],
        "symbol": data.get('symbol'),
        "name": data['name'],
        "quantity": data['quantity'],
        "cost_basis": data.get('cost_basis', 0),
        "currency": data.get('currency', 'BRL'),
    }
    res = client.from_("investments").insert(payload).execute()
    return res.data

def update_investment(inv_id, user_id, data):
    client = get_pg()
    # Security check: policy handles it, but good to be explicit
    res = client.from_("investments").update(data).eq("id", inv_id).eq("user_id", user_id).execute()
    return res.data

def delete_investment(inv_id, user_id):
    client = get_pg()
    res = client.from_("investments").delete().eq("id", inv_id).eq("user_id", user_id).execute()
    return res.data

def get_portfolio_distribution_by_type(user_id, investment_types=None):
    """
    Get portfolio distribution aggregated by investment type for pie chart.
    
    Args:
        user_id: User ID to fetch investments for
        investment_types: Optional list of investment types to filter (e.g., ['stock', 'crypto'])
                         If None, includes all types
    
    Returns:
        {
            "distribution": [
                {"type": "stock", "value_usd": 1000.0, "value_brl": 5000.0, "percentage": 50.0},
                {"type": "crypto", "value_usd": 500.0, "value_brl": 2500.0, "percentage": 25.0},
                ...
            ],
            "total_value_usd": 2000.0,
            "total_value_brl": 10000.0,
            "exchange_rate_usd_brl": 5.0,
            "items": [...] # Only included when filtering by single type
        }
    """
    # Fetch the full portfolio
    portfolio = fetch_portfolio(user_id)
    
    if not portfolio['investments']:
        return {
            "distribution": [],
            "total_value_usd": 0.0,
            "total_value_brl": 0.0,
            "exchange_rate_usd_brl": portfolio.get('exchange_rate_usd_brl', 5.0)
        }
    
    # Check if filtering by single type - if so, return individual investments
    show_individual = investment_types and len(investment_types) == 1
    
    if show_individual:
        # Return individual investments within the type
        filtered_type = investment_types[0]
        items = []
        total_usd = 0.0
        total_brl = 0.0
        
        for inv in portfolio['investments']:
            if inv['type'].lower() == filtered_type.lower():
                val_usd = inv['current_value_usd']
                val_brl = inv['current_value_brl']
                
                items.append({
                    'id': inv.get('id'),
                    'name': inv['name'],
                    'symbol': inv.get('symbol'),
                    'type': inv['type'],
                    'value_usd': val_usd,
                    'value_brl': val_brl,
                    'quantity': inv['quantity'],
                })
                
                total_usd += val_usd
                total_brl += val_brl
        
        # Sort by value descending
        items.sort(key=lambda x: x['value_usd'], reverse=True)
        
        # Calculate percentages
        for item in items:
            item['percentage'] = (item['value_usd'] / total_usd * 100) if total_usd > 0 else 0.0
        
        return {
            "distribution": [{
                'type': filtered_type,
                'value_usd': total_usd,
                'value_brl': total_brl,
                'percentage': 100.0
            }],
            "items": items,
            "total_value_usd": total_usd,
            "total_value_brl": total_brl,
            "exchange_rate_usd_brl": portfolio.get('exchange_rate_usd_brl', 5.0)
        }
    
    # Aggregate by type (original behavior)
    type_aggregates = {}
    total_usd = 0.0
    total_brl = 0.0
    
    for inv in portfolio['investments']:
        inv_type = inv['type']
        
        # Filter by investment types if specified
        if investment_types and inv_type not in investment_types:
            continue
        
        val_usd = inv['current_value_usd']
        val_brl = inv['current_value_brl']
        
        if inv_type not in type_aggregates:
            type_aggregates[inv_type] = {
                'value_usd': 0.0,
                'value_brl': 0.0
            }
        
        type_aggregates[inv_type]['value_usd'] += val_usd
        type_aggregates[inv_type]['value_brl'] += val_brl
        total_usd += val_usd
        total_brl += val_brl
    
    # Build distribution array with percentages
    distribution = []
    for inv_type, values in type_aggregates.items():
        percentage = (values['value_usd'] / total_usd * 100) if total_usd > 0 else 0.0
        distribution.append({
            'type': inv_type,
            'value_usd': values['value_usd'],
            'value_brl': values['value_brl'],
            'percentage': round(percentage, 2)
        })
    
    # Sort by value descending
    distribution.sort(key=lambda x: x['value_usd'], reverse=True)
    
    return {
        "distribution": distribution,
        "total_value_usd": total_usd,
        "total_value_brl": total_brl,
        "exchange_rate_usd_brl": portfolio.get('exchange_rate_usd_brl', 5.0)
    }

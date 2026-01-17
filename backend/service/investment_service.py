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

    # Sanity checks
    if usd_to_brl <= 0.1: usd_to_brl = 5.0
    if eur_to_usd <= 0.1: eur_to_usd = 1.0
    if usd_to_pln <= 0.1: usd_to_pln = 4.0

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

from datetime import date, timedelta
from dateutil.relativedelta import relativedelta

def get_billing_period(spent_at: date, is_credit_card: bool, closing_day: int = 23):
    """
    Determines the billing month/year for a given expense.
    
    If Credit Card:
      - If day < closing_day: Belongs to current month.
      - If day >= closing_day: Belongs to next month.
    
    If Cash/Pix:
      - Always belongs to current month.
    """
    if not is_credit_card:
        return spent_at.month, spent_at.year
    
    if spent_at.day >= closing_day:
        # Move to next month
        next_month_date = spent_at + relativedelta(months=1)
        return next_month_date.month, next_month_date.year
    
    return spent_at.month, spent_at.year

def get_query_range_for_month(billing_month: int, billing_year: int, closing_day: int = 23):
    """
    Returns the absolute min and max dates ensuring we cover all transactions 
    that COULD belong to this billing month.
    
    Cash/Pix: Month 1st to Month End.
    Credit Card: Prev Month 23rd to Month 22nd (if closing_day=23).
    
    We need to fetch from (PrevMonth [closing_day]) to (Month End).
    """
    target_date = date(billing_year, billing_month, 1)
    
    # Start: Look back to previous month for Credit Card overlapping transactions
    prev_month = target_date - relativedelta(months=1)
    
    # Ensure closing_day is valid for previous month (e.g. Feb 30 -> Feb 28)
    # But simple replace usually works if day is valid. 
    # For safety with variable days (like 31), we might need robust handling, 
    # but for query range start, if the prev month has fewer days than closing_day,
    # the credit card logic effectively starts late or needs adjustment.
    # However, for SQL query purposes, using a safe day 'min(closing_day, last_day_of_prev_month)' is safer.
    import calendar
    last_day_prev = calendar.monthrange(prev_month.year, prev_month.month)[1]
    safe_closing_day = min(closing_day, last_day_prev)
    
    start_date = prev_month.replace(day=safe_closing_day)
    
    # End: End of the target month (for Cash/Pix)
    # The billing cycle for CC ends on the (closing_day - 1) of target month, 
    # but Cash ends on 31st. So max date is end of month.
    next_month = target_date + relativedelta(months=1)
    end_date = next_month - timedelta(days=1)
    
    return start_date, end_date

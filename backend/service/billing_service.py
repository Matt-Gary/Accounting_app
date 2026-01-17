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
    Credit Card: Prev Month 23rd to Month 22nd.
    
    So we need to fetch from (PrevMonth 23rd) to (Month End).
    """
    target_date = date(billing_year, billing_month, 1)
    
    # Start: Look back to previous month for Credit Card overlapping transactions
    prev_month = target_date - relativedelta(months=1)
    start_date = prev_month.replace(day=closing_day)
    
    # End: End of the target month (for Cash/Pix)
    # The billing cycle for CC ends on the 22nd of target month, 
    # but Cash ends on 31st. So max date is end of month.
    next_month = target_date + relativedelta(months=1)
    end_date = next_month - timedelta(days=1)
    
    return start_date, end_date

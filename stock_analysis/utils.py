import numpy as np

def clean_amount(val):
    s = str(val).strip()
    if s.startswith('(') and s.endswith(')'):
        s = '-' + s[1:-1]
    s = s.replace('$', '').replace(',', '')
    try:
        return float(s)
    except:
        return np.nan

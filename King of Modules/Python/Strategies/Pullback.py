import pandas as pd
from Config import Signal
 
 
def signal_pullback(rates: pd.DataFrame) -> Signal:
    """Stub. Returns Signal.NONE (matches MQL5 SignalPullback stub)."""
    return Signal.NONE
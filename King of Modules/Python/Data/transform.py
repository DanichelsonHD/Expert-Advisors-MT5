import os
import pandas as pd

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

input_file = os.path.join(BASE_DIR, "EURUSD_M1.csv")

df = pd.read_csv(input_file)


df["time"] = pd.to_datetime(df["time"])
df.set_index("time", inplace=True)

m15 = df.resample("15T").agg({
    "open":"first",
    "high":"max",
    "low":"min",
    "close":"last",
    "tick_volume":"sum"
})

h1 = df.resample("1H").agg({
    "open":"first",
    "high":"max",
    "low":"min",
    "close":"last",
    "tick_volume":"sum"
})

#m15.to_csv("Data/XAUUSD_M15.csv")
output = os.path.join(BASE_DIR, "EURUSD_H1.csv")
h1.to_csv(output)
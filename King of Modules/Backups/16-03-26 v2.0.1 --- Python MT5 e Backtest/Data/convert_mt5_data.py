import pandas as pd
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

INPUT_FILE = os.path.join(BASE_DIR, "EURUSD_H1_201501020900_202603162000.csv")
OUTPUT_FILE = os.path.join(BASE_DIR, "EURUSD_H1.csv")

print("Loading MT5 file...")

df = pd.read_csv(INPUT_FILE, delimiter="\t")

print("Columns detected:")
print(df.columns)

df = df.rename(columns={
    "<DATE>": "date",
    "<TIME>": "time",
    "<OPEN>": "open",
    "<HIGH>": "high",
    "<LOW>": "low",
    "<CLOSE>": "close",
    "<TICKVOL>": "tick_volume"
})

df["time"] = pd.to_datetime(df["date"] + " " + df["time"])

df = df[["time","open","high","low","close","tick_volume"]]

df.to_csv(OUTPUT_FILE, index=False)

print("Conversion finished.")
print("Saved to:", OUTPUT_FILE)
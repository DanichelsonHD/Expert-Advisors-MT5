import pandas as pd
import mplfinance as mpf


def plot_chart(df, trades):

    # garantir datetime
    df = df.copy()
    df.index = pd.to_datetime(df.index)

    # limitar candles para performance
    df = df.tail(3000)

    # -----------------------------
    # indicadores
    # -----------------------------

    if "ema_50" not in df.columns:
        df["ema_50"] = df["close"].ewm(span=50).mean()

    if "rsi_4" not in df.columns:
        delta = df["close"].diff()

        gain = delta.clip(lower=0)
        loss = -delta.clip(upper=0)

        avg_gain = gain.rolling(4).mean()
        avg_loss = loss.rolling(4).mean()

        rs = avg_gain / avg_loss
        df["rsi_4"] = 100 - (100 / (1 + rs))

    ema = df["ema_50"]
    rsi = df["rsi_4"]

    # -----------------------------
    # criar séries vazias
    # -----------------------------

    buy_series = pd.Series(index=df.index, dtype=float)
    sell_series = pd.Series(index=df.index, dtype=float)

    # -----------------------------
    # mapear trades para candles
    # -----------------------------

    for t in trades:

        ts = pd.to_datetime(t.entry_time)

        # pegar candle mais próximo
        idx = df.index.get_indexer([ts], method="nearest")[0]

        if idx == -1:
            continue

        candle_time = df.index[idx]

        if t.direction == "BUY":
            buy_series.loc[candle_time] = t.entry_price
        else:
            sell_series.loc[candle_time] = t.entry_price

    # -----------------------------
    # plots
    # -----------------------------

    apds = []

    # EMA overlay
    apds.append(
        mpf.make_addplot(
            ema,
            color="blue",
            width=1
        )
    )

    # RSI painel inferior
    apds.append(
        mpf.make_addplot(
            rsi,
            panel=1,
            color="purple",
            ylabel="RSI"
        )
    )

    # BUY markers
    apds.append(
        mpf.make_addplot(
            buy_series,
            type="scatter",
            marker="^",
            markersize=100,
            color="green"
        )
    )

    # SELL markers
    apds.append(
        mpf.make_addplot(
            sell_series,
            type="scatter",
            marker="v",
            markersize=100,
            color="red"
        )
    )

    # -----------------------------
    # plot
    # -----------------------------

    mpf.plot(
        df,
        type="candle",
        style="charles",
        addplot=apds,
        volume=False,
        figsize=(14,8),
        panel_ratios=(3,1),
        warn_too_much_data=100000
    )
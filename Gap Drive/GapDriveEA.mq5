//+------------------------------------------------------------------+
//|                                               GapDriveEA.mq5    |
//|           Gap Drive — Fully Autonomous MT5 Expert Advisor        |
//|           Self-contained. No iCustom. No indicator buffers.      |
//+------------------------------------------------------------------+
#property copyright   "Gap Drive EA"
#property version     "1.00"
#property strict

#include "GapDriveCore.mqh"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Gap Detection
input group "=== GAP DETECTION ==="
input int    InpGapHour          = 1;       // Gap candle hour (server time)
input int    InpGapMinute        = 0;       // Gap candle minute (server time)
input double InpMinGapPoints     = 30.0;    // Minimum gap size in points
input double InpMaxGapPoints     = 10000.0; // Maximum gap size in points

//--- True Gap Filter
input group "=== TRUE GAP FILTER ==="
input bool   InpRequireTrueGap      = true;  // Require wick-based true gap
input double InpMinTrueGapPoints    = 0.0;   // Minimum wick gap size in points

//--- Reverse Mode
input group "=== DIRECTION ==="
input bool   InpReverseMode         = false; // Invert trade direction

//--- Entry Mode
input group "=== ENTRY MODE ==="
input ENTRY_MODE InpEntryMode       = ENTRY_REFERENCE; // Entry price mode
input double     InpTargetRR        = 2.0;             // Target reward/risk ratio (RR Offset mode)

//--- Stop Mode
input group "=== STOP MODE ==="
input STOP_MODE  InpStopMode        = STOP_SECOND_CANDLE_EXTREME; // Stop loss calculation mode

//--- Expiration
input group "=== EXPIRATION ==="
input int    InpExpirationCandles   = 48;   // Candles before setup expires (no entry)

//--- Money Management
input group "=== MONEY MANAGEMENT ==="
input ENUM_LOT_MODE InpLotMode          = LOT_MODE_FIXED;       // Lot Sizing Mode
input double        InpFixedLot         = 0.1;                  // Fixed Lot size (if Fixed Mode)
input double        InpRiskPercent      = 1.0;                  // Risk % of Account Balance per trade
input double        InpTargetProfitUSD  = 100.0;                // Target profit in USD to win on TP

//--- Trade Execution
input group "=== TRADE EXECUTION ==="
input int    InpSlippage            = 3;    // Maximum slippage in points
input ulong  InpMagicNumber         = 20240001; // EA magic number

//--- Reversal Module
input group "=== REVERSAL MODULE ==="
input bool            InpEnableReversal    = false;           // Enable reversal module
input REVERSAL_TARGET InpReversalTarget    = TARGET_REFERENCE; // Reversal target mode
input int             InpReversalExpCandles = 48;             // Expiration for reversal setups

//--- Statistics / Debug
input group "=== STATISTICS ==="
input bool   InpDebugStatistics     = true;  // Print statistics to journal

//--- Visual Panel
input group "=== PANEL ==="
input bool   InpShowPanel           = true;  // Show statistics panel on chart

//+------------------------------------------------------------------+
//| GLOBAL STATE                                                      |
//+------------------------------------------------------------------+

GapSetup   g_setups[];
int        g_setupCount    = 0;

StatsBlock g_stats;        // Primary setup statistics
StatsBlock g_revStats;     // Reversal setup statistics

CTrade     g_trade;

//--- Panel label names
const string PANEL_PREFIX      = "GDEA_Panel_L";
const int    PANEL_LINE_COUNT  = 14;
const int    PANEL_LINE_HEIGHT = 14;
const int    PANEL_X_POS      = 10;
const int    PANEL_Y_START     = 20;

//--- Tracks the last bar time processed for gap detection (prevents duplicate detection)
datetime   g_lastDetectionBar  = 0;

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(g_setups, 0);
   g_setupCount = 0;

   ZeroMemory(g_stats);
   ZeroMemory(g_revStats);

   g_lastDetectionBar = 0;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpSlippage);
   g_trade.SetTypeFilling(ORDER_FILLING_FOK);

   if(InpShowPanel)
      CreatePanel();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpShowPanel)
      DestroyPanel();
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // Minimum bars required: need at least the previous candle + gap candle + 1 closed
   const int rates_total = Bars(_Symbol, PERIOD_CURRENT);
   if(rates_total < 3)
      return;

   // --- STEP 1: Detect new gap setups on newly closed candles ---
   // We look at bar index 2 (i+1 in indicator terms) as the "gap candle"
   // and bar index 3 as the "previous candle", because bar 0 = live forming bar,
   // bar 1 = last closed bar. Both reference candles must be fully closed.
   DetectNewSetups();

   // --- STEP 2: Manage open positions (track TP/SL hits) ---
   ManageActivePositions();

   // --- STEP 3: Monitor pending setups for entry trigger ---
   MonitorPendingSetups();

   // --- STEP 4: Expire stale setups ---
   ExpireSetups();

   // --- STEP 5: Update visual panel ---
   if(InpShowPanel)
      UpdatePanel();

   // --- STEP 6: Debug output ---
   if(InpDebugStatistics)
      PrintStatistics();
}

//+------------------------------------------------------------------+
//| DetectNewSetups                                                   |
//| Scans closed bars and registers gap setups.                       |
//| Only processes each closed bar once.                              |
//+------------------------------------------------------------------+
void DetectNewSetups()
{
   // bar[0]  = currently forming (live) — EXCLUDED
   // bar[1]  = last closed bar
   // bar[2]  = second-to-last closed bar
   // We need bar[1] as the "gap candle" and bar[2] as the "previous candle"
   // i.e. both must be fully closed. We scan backward from bar[1].

   // Retrieve enough bars for scanning
   const int lookback = MathMax(InpExpirationCandles + 10, 200);

   datetime timeBuf[];
   double   openBuf[], highBuf[], lowBuf[], closeBuf[];

   const int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, lookback,
                                timeBuf, openBuf, highBuf, lowBuf, closeBuf);
   if(copied < 3)
      return;

   // copied bars: index 0 = oldest, index copied-1 = most recent (live forming bar)
   // Exclude index copied-1 (live bar) from both gap candle and previous candle.
   // Upper limit for "gap candle" position = copied - 2 (second most recent = last closed)
   // Lower limit = 1 (needs at least one previous candle at index 0)

   for(int i = copied - 2; i >= 1; i--)
   {
      // i   = candidate "gap candle"   (fully closed)
      // i-1 = candidate "previous candle" (fully closed)

      const datetime gapCandleTime = timeBuf[i];

      // Only process candles we haven't seen yet
      if(gapCandleTime <= g_lastDetectionBar)
         break;   // older candles already processed in previous ticks

      if(!IsGapBar(gapCandleTime, InpGapHour, InpGapMinute))
         continue;

      if(SetupAlreadyExists(gapCandleTime))
         continue;

      const double openPrev  = openBuf[i - 1];
      const double closePrev = closeBuf[i - 1];
      const double highPrev  = highBuf[i - 1];
      const double lowPrev   = lowBuf[i - 1];

      const double openCurr  = openBuf[i];
      const double closeCurr = closeBuf[i];
      const double highCurr  = highBuf[i];
      const double lowCurr   = lowBuf[i];

      double gapTop    = 0.0;
      double gapBottom = 0.0;
      bool   isLong    = false;

      if(!CalcGap(openPrev, closePrev, openCurr, closeCurr, gapTop, gapBottom, isLong))
         continue;

      // True gap wick filter
      if(InpRequireTrueGap)
      {
         if(!PassesTrueGapFilter(isLong,
                                 highPrev, lowPrev,
                                 highCurr, lowCurr,
                                 InpMinTrueGapPoints))
            continue;
      }

      const double gapSize       = gapTop - gapBottom;
      const double gapSizePoints = gapSize / _Point;

      if(!ValidateGap(gapSizePoints, InpMinGapPoints, InpMaxGapPoints))
         continue;

      // Apply reverse mode: invert direction for level generation
      const bool effectiveIsLong = InpReverseMode ? !isLong : isLong;

      double refEntry = 0.0, stopPrice = 0.0, targetPrice = 0.0;
      GenerateLevels(gapTop, gapBottom, gapSize, effectiveIsLong,
                     highCurr, lowCurr, InpStopMode,
                     refEntry, stopPrice, targetPrice);

      // RR-based entry repositioning
      double effectiveEntry = refEntry;
      if(InpEntryMode == ENTRY_RR_OFFSET)
      {
         const double rrEntry = CalculateRRBasedEntry(effectiveIsLong,
                                                      stopPrice,
                                                      targetPrice,
                                                      InpTargetRR);
         if(ValidateRREntry(effectiveIsLong, rrEntry, stopPrice, targetPrice))
            effectiveEntry = rrEntry;
         else
            Print("GapDriveEA: RR entry rejected — falling back to reference entry");
      }

      // Build and store the setup
      GapSetup setup;
      ZeroMemory(setup);
      setup.gap_time        = gapCandleTime;
      setup.bullish_gap     = effectiveIsLong;
      setup.bearish_gap     = !effectiveIsLong;
      setup.trigger_price   = effectiveEntry;
      setup.stop_price      = stopPrice;
      setup.target_price    = targetPrice;
      setup.reference_entry = refEntry;
      setup.gap_top         = gapTop;
      setup.gap_bottom      = gapBottom;
      setup.gap_size        = gapSize;
      setup.triggered       = false;
      setup.finished        = false;
      setup.expired         = false;
      setup.position_ticket = 0;
      setup.state           = WAITING_ENTRY;
      setup.gap_bar_index   = i;   // position within current copy buffer
      setup.is_reversal     = false;

      int sz = ArraySize(g_setups);
      ArrayResize(g_setups, sz + 1);
      g_setups[sz] = setup;
      g_setupCount++;

      g_stats.detected++;

      PrintFormat("GapDriveEA: New setup detected | Time=%s | %s | Entry=%.5f | SL=%.5f | TP=%.5f",
                  TimeToString(gapCandleTime, TIME_DATE | TIME_MINUTES),
                  effectiveIsLong ? "BUY" : "SELL",
                  effectiveEntry,
                  stopPrice,
                  targetPrice);
   }

   // Advance the detection marker to the last closed bar's time
   if(copied >= 2)
      g_lastDetectionBar = timeBuf[copied - 2];
}

//+------------------------------------------------------------------+
//| SetupAlreadyExists                                                |
//| Returns true if a setup with the same gap_time exists.            |
//+------------------------------------------------------------------+
bool SetupAlreadyExists(const datetime t)
{
   const int total = ArraySize(g_setups);
   for(int i = 0; i < total; i++)
   {
      if(g_setups[i].gap_time == t)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| CopyRates overload (fills separate arrays)                        |
//+------------------------------------------------------------------+
int CopyRates(const string   symbol,
              const ENUM_TIMEFRAMES tf,
              const int      startPos,
              const int      count,
              datetime      &timeBuf[],
              double        &openBuf[],
              double        &highBuf[],
              double        &lowBuf[],
              double        &closeBuf[])
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   const int copied = ::CopyRates(symbol, tf, startPos, count, rates);
   if(copied <= 0)
      return 0;

   ArrayResize(timeBuf,  copied);
   ArrayResize(openBuf,  copied);
   ArrayResize(highBuf,  copied);
   ArrayResize(lowBuf,   copied);
   ArrayResize(closeBuf, copied);

   for(int i = 0; i < copied; i++)
   {
      timeBuf[i]  = rates[i].time;
      openBuf[i]  = rates[i].open;
      highBuf[i]  = rates[i].high;
      lowBuf[i]   = rates[i].low;
      closeBuf[i] = rates[i].close;
   }
   return copied;
}

//+------------------------------------------------------------------+
//| MonitorPendingSetups                                              |
//| Checks if current price touches the trigger of any pending setup. |
//| Executes market order when triggered.                             |
//+------------------------------------------------------------------+
void MonitorPendingSetups()
{
   const int total = ArraySize(g_setups);
   for(int s = 0; s < total; s++)
   {
      if(g_setups[s].state != WAITING_ENTRY)
         continue;

      if(g_setups[s].triggered || g_setups[s].expired || g_setups[s].finished)
         continue;

      const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool triggered = false;

      if(g_setups[s].bullish_gap)
      {
         // BUY: ask touches or crosses trigger (price fell to entry)
         if(ask <= g_setups[s].trigger_price)
            triggered = true;
      }
      else
      {
         // SELL: bid touches or crosses trigger (price rose to entry)
         if(bid >= g_setups[s].trigger_price)
            triggered = true;
      }

      if(!triggered)
         continue;

      // Mark as triggered before execution attempt
      g_setups[s].triggered = true;
      g_setups[s].state     = TRADE_ACTIVE;

      if(!g_setups[s].is_reversal)
         g_stats.triggered++;
      else
         g_revStats.triggered++;

      // Execute trade
      ExecuteTrade(s);
   }
}

//+------------------------------------------------------------------+
//| ExecuteTrade                                                      |
//| Opens a market order for the given setup index.                   |
//+------------------------------------------------------------------+
void ExecuteTrade(const int setupIdx)
{
   const double lots = CalculateLotSize(_Symbol,
                                        InpLotMode,
                                        InpFixedLot,
                                        InpRiskPercent,
                                        InpTargetProfitUSD,
                                        g_setups[setupIdx].trigger_price,
                                        g_setups[setupIdx].stop_price,
                                        g_setups[setupIdx].target_price);

   if(lots <= 0.0)
   {
      PrintFormat("GapDriveEA: Trade skipped (lot calc returned 0) | Mode=%d | Entry=%.5f SL=%.5f TP=%.5f",
                  (int)InpLotMode,
                  g_setups[setupIdx].trigger_price,
                  g_setups[setupIdx].stop_price,
                  g_setups[setupIdx].target_price);

      // Revert state so setup can retry or expire naturally
      g_setups[setupIdx].state     = WAITING_ENTRY;
      g_setups[setupIdx].triggered = false;
      if(!g_setups[setupIdx].is_reversal)
         g_stats.triggered--;
      else
         g_revStats.triggered--;
      return;
   }

   const double sl = NormalizeDouble(g_setups[setupIdx].stop_price,  (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   const double tp = NormalizeDouble(g_setups[setupIdx].target_price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

   bool result = false;

   if(g_setups[setupIdx].bullish_gap)
      result = g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "GapDriveEA");
   else
      result = g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "GapDriveEA");

   if(result)
   {
      g_setups[setupIdx].position_ticket = g_trade.ResultDeal();
      PrintFormat("GapDriveEA: Trade opened | %s | Lots=%.2f | Ticket=%llu | SL=%.5f | TP=%.5f",
                  g_setups[setupIdx].bullish_gap ? "BUY" : "SELL",
                  lots,
                  g_setups[setupIdx].position_ticket,
                  sl, tp);
   }
   else
   {
      PrintFormat("GapDriveEA: Trade execution failed | Error=%d | Retcode=%d",
                  GetLastError(),
                  g_trade.ResultRetcode());
      // Revert state so setup can retry or expire naturally
      g_setups[setupIdx].state     = WAITING_ENTRY;
      g_setups[setupIdx].triggered = false;
      if(!g_setups[setupIdx].is_reversal)
         g_stats.triggered--;
      else
         g_revStats.triggered--;
   }
}

//+------------------------------------------------------------------+
//| ManageActivePositions                                             |
//| Checks if any active position has been closed (TP or SL).        |
//| Updates statistics and optionally spawns reversal setup.          |
//+------------------------------------------------------------------+
void ManageActivePositions()
{
   const int total = ArraySize(g_setups);
   for(int s = 0; s < total; s++)
   {
      if(g_setups[s].state != TRADE_ACTIVE)
         continue;

      if(g_setups[s].finished)
         continue;

      const ulong ticket = g_setups[s].position_ticket;
      if(ticket == 0)
         continue;

      // Check if position still exists
      if(PositionSelectByTicket(ticket))
         continue;   // still open — nothing to do

      // Position is closed — determine outcome from deal history
      bool isWin  = false;
      bool isLoss = false;
      ResolveTradeOutcome(ticket, g_setups[s].bullish_gap, isWin, isLoss);

      g_setups[s].finished = true;
      g_setups[s].state    = TRADE_FINISHED;

      if(isWin)
      {
         if(!g_setups[s].is_reversal)
            g_stats.wins++;
         else
            g_revStats.wins++;

         PrintFormat("GapDriveEA: Trade WIN | Ticket=%llu", ticket);

         // Reversal module: spawn opposite setup on primary TP hit
         if(!g_setups[s].is_reversal && InpEnableReversal && isWin)
            SpawnReversalSetup(s);
      }
      else if(isLoss)
      {
         if(!g_setups[s].is_reversal)
            g_stats.losses++;
         else
            g_revStats.losses++;

         PrintFormat("GapDriveEA: Trade LOSS | Ticket=%llu", ticket);
      }
      else
      {
         // Closed at breakeven or unknown — count as loss conservatively
         if(!g_setups[s].is_reversal)
            g_stats.losses++;
         else
            g_revStats.losses++;

         PrintFormat("GapDriveEA: Trade CLOSED (BE/unknown) | Ticket=%llu", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| ResolveTradeOutcome                                               |
//| Inspects deal history to determine win/loss for a closed ticket.  |
//+------------------------------------------------------------------+
void ResolveTradeOutcome(const ulong ticket,
                         const bool  isBuy,
                         bool       &isWin,
                         bool       &isLoss)
{
   isWin  = false;
   isLoss = false;

   if(!HistorySelectByPosition(ticket))
      return;

   const int dealsTotal = HistoryDealsTotal();
   double    profit     = 0.0;

   for(int d = 0; d < dealsTotal; d++)
   {
      const ulong dealTicket = HistoryDealGetTicket(d);
      if(dealTicket == 0)
         continue;

      const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      profit += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   }

   if(profit > 0.0)
      isWin = true;
   else if(profit < 0.0)
      isLoss = true;
   // profit == 0.0 → breakeven, neither flag set
}

//+------------------------------------------------------------------+
//| SpawnReversalSetup                                                |
//| Creates a new setup in the opposite direction when primary TP hit.|
//+------------------------------------------------------------------+
void SpawnReversalSetup(const int primaryIdx)
{
   const GapSetup primary = g_setups[primaryIdx];

   // Reversal direction is opposite to primary
   const bool revIsLong = !primary.bullish_gap;

   double revEntry  = 0.0;
   double revStop   = 0.0;
   double revTarget = 0.0;

   if(InpReversalTarget == TARGET_REFERENCE)
   {
      // Entry at the primary TP (gap edge opposite), target at primary entry reference
      if(revIsLong)
      {
         revEntry  = primary.target_price;   // bottom of gap
         revTarget = primary.gap_top;
         revStop   = revEntry - primary.gap_size;
         if(revStop > revEntry - primary.gap_size)
            revStop = revEntry - primary.gap_size;
      }
      else
      {
         revEntry  = primary.target_price;   // top of gap
         revTarget = primary.gap_bottom;
         revStop   = revEntry + primary.gap_size;
      }
   }
   else // TARGET_GAP_FILL
   {
      // Entry at TP, target at the opposite gap edge (full fill)
      revEntry  = primary.target_price;
      if(revIsLong)
      {
         revTarget = primary.gap_top;
         revStop   = revEntry - primary.gap_size;
      }
      else
      {
         revTarget = primary.gap_bottom;
         revStop   = revEntry + primary.gap_size;
      }
   }

   GapSetup rev;
   ZeroMemory(rev);
   rev.gap_time        = TimeCurrent();
   rev.bullish_gap     = revIsLong;
   rev.bearish_gap     = !revIsLong;
   rev.trigger_price   = revEntry;
   rev.stop_price      = revStop;
   rev.target_price    = revTarget;
   rev.reference_entry = revEntry;
   rev.gap_top         = primary.gap_top;
   rev.gap_bottom      = primary.gap_bottom;
   rev.gap_size        = primary.gap_size;
   rev.triggered       = false;
   rev.finished        = false;
   rev.expired         = false;
   rev.position_ticket = 0;
   rev.state           = WAITING_ENTRY;
   rev.gap_bar_index   = 0;   // not relevant for reversal; expiration uses TimeCurrent
   rev.is_reversal     = true;

   const int sz = ArraySize(g_setups);
   ArrayResize(g_setups, sz + 1);
   g_setups[sz] = rev;
   g_setupCount++;

   g_revStats.detected++;

   PrintFormat("GapDriveEA: Reversal setup spawned | %s | Entry=%.5f | SL=%.5f | TP=%.5f",
               revIsLong ? "BUY" : "SELL",
               revEntry, revStop, revTarget);
}

//+------------------------------------------------------------------+
//| ExpireSetups                                                      |
//| Marks setups as expired after InpExpirationCandles closed bars.   |
//+------------------------------------------------------------------+
void ExpireSetups()
{
   const int total = ArraySize(g_setups);
   if(total == 0)
      return;

   // Get current bar count for elapsed-bar computation
   datetime timeBuf[];
   ArraySetAsSeries(timeBuf, false);
   const int copied = CopyTime(_Symbol, PERIOD_CURRENT, 0,
                                InpExpirationCandles + 10, timeBuf);
   if(copied < 2)
      return;

   // Most recent closed bar time = timeBuf[copied - 2]
   // (timeBuf[copied-1] is live bar)
   const datetime lastClosedBarTime = timeBuf[copied - 2];
   const int      periodSec         = PeriodSeconds();

   for(int s = 0; s < total; s++)
   {
      if(g_setups[s].state != WAITING_ENTRY)
         continue;
      if(g_setups[s].expired || g_setups[s].finished || g_setups[s].triggered)
         continue;

      // Calculate bars elapsed since gap_time (approximate, using time diff)
      const int barsSinceGap = (int)MathRound(
         (double)(lastClosedBarTime - g_setups[s].gap_time) / (double)periodSec);

      const int expCandles = g_setups[s].is_reversal
                             ? InpReversalExpCandles
                             : InpExpirationCandles;

      if(barsSinceGap >= expCandles)
      {
         g_setups[s].expired = true;
         g_setups[s].state   = EXPIRED;

         if(!g_setups[s].is_reversal)
            g_stats.expired++;
         else
            g_revStats.expired++;

         PrintFormat("GapDriveEA: Setup expired | Time=%s | %s",
                     TimeToString(g_setups[s].gap_time, TIME_DATE | TIME_MINUTES),
                     g_setups[s].bullish_gap ? "BUY" : "SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| PrintStatistics                                                   |
//| Outputs statistics summary to the Experts journal.                |
//+------------------------------------------------------------------+
void PrintStatistics()
{
   static int s_lastDetected = -1;
   if(g_stats.detected == s_lastDetected)
      return;

   s_lastDetected = g_stats.detected;

   const int resolved   = g_stats.wins + g_stats.losses;
   const double winRate = (resolved > 0) ? (100.0 * g_stats.wins / resolved) : 0.0;

   Print("--- GapDriveEA PRIMARY STATISTICS ---");
   PrintFormat("Detected  : %d", g_stats.detected);
   PrintFormat("Triggered : %d", g_stats.triggered);
   PrintFormat("Wins      : %d", g_stats.wins);
   PrintFormat("Losses    : %d", g_stats.losses);
   PrintFormat("Expired   : %d", g_stats.expired);
   PrintFormat("Win Rate  : %.1f %%", winRate);

   if(InpEnableReversal)
   {
      const int revResolved   = g_revStats.wins + g_revStats.losses;
      const double revWinRate = (revResolved > 0) ? (100.0 * g_revStats.wins / revResolved) : 0.0;

      Print("--- GapDriveEA REVERSAL STATISTICS ---");
      PrintFormat("Rev Detected  : %d", g_revStats.detected);
      PrintFormat("Rev Triggered : %d", g_revStats.triggered);
      PrintFormat("Rev Wins      : %d", g_revStats.wins);
      PrintFormat("Rev Losses    : %d", g_revStats.losses);
      PrintFormat("Rev Expired   : %d", g_revStats.expired);
      PrintFormat("Rev Win Rate  : %.1f %%", revWinRate);
   }
}

//+------------------------------------------------------------------+
//| PANEL FUNCTIONS                                                   |
//+------------------------------------------------------------------+

string PanelLineName(const int line)
{
   return PANEL_PREFIX + IntegerToString(line);
}

void CreatePanel()
{
   for(int i = 0; i < PANEL_LINE_COUNT; i++)
   {
      const string name = PanelLineName(i);
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  PANEL_X_POS);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  PANEL_Y_START + i * PANEL_LINE_HEIGHT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      clrWhite);
      ObjectSetString (0, name, OBJPROP_FONT,       "Courier New");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
}

void DestroyPanel()
{
   for(int i = 0; i < PANEL_LINE_COUNT; i++)
      ObjectDelete(0, PanelLineName(i));
   ChartRedraw(0);
}

void UpdatePanel()
{
   const int    resolved = g_stats.wins + g_stats.losses;
   const double winRate  = (resolved > 0) ? (100.0 * g_stats.wins / resolved) : 0.0;

   color winRateColor;
   if(winRate >= 70.0)      winRateColor = clrLime;
   else if(winRate >= 50.0) winRateColor = clrGold;
   else                     winRateColor = clrRed;

   string entryModeStr = (InpEntryMode == ENTRY_RR_OFFSET) ? "RR Offset" : "Reference";
   string stopModeStr  = (InpStopMode  == STOP_SYMMETRIC)  ? "Symmetric" : "2nd Candle Ext";
   string modeStr      = InpReverseMode ? "REVERSE" : "NORMAL";

   string lines[14];
   lines[0]  = "GAP DRIVE EA";
   lines[1]  = "Mode      : " + modeStr;
   lines[2]  = "Entry     : " + entryModeStr;
   lines[3]  = "Stop      : " + stopModeStr;
   lines[4]  = (InpEntryMode == ENTRY_RR_OFFSET)
               ? "Target RR : " + DoubleToString(InpTargetRR, 1)
               : "";
   lines[5]  = "---Primary---";
   lines[6]  = "Detected  : " + IntegerToString(g_stats.detected);
   lines[7]  = "Triggered : " + IntegerToString(g_stats.triggered);
   lines[8]  = "Wins      : " + IntegerToString(g_stats.wins);
   lines[9]  = "Losses    : " + IntegerToString(g_stats.losses);
   lines[10] = "Expired   : " + IntegerToString(g_stats.expired);
   lines[11] = "Win Rate  : " + DoubleToString(winRate, 1) + " %";
   lines[12] = InpEnableReversal
               ? "Rev W/L   : " + IntegerToString(g_revStats.wins)
                 + "/" + IntegerToString(g_revStats.losses)
               : "";
   lines[13] = "Expiry    : " + IntegerToString(InpExpirationCandles) + " bars";

   color lineColors[14];
   lineColors[0]  = clrWhite;
   lineColors[1]  = clrWhite;
   lineColors[2]  = clrWhite;
   lineColors[3]  = clrWhite;
   lineColors[4]  = clrGold;
   lineColors[5]  = clrSilver;
   lineColors[6]  = clrWhite;
   lineColors[7]  = clrWhite;
   lineColors[8]  = clrLime;
   lineColors[9]  = clrRed;
   lineColors[10] = clrWhite;
   lineColors[11] = winRateColor;
   lineColors[12] = clrGold;
   lineColors[13] = clrWhite;

   for(int i = 0; i < PANEL_LINE_COUNT; i++)
   {
      ObjectSetString (0, PanelLineName(i), OBJPROP_TEXT,  lines[i]);
      ObjectSetInteger(0, PanelLineName(i), OBJPROP_COLOR, lineColors[i]);
   }

   ChartRedraw(0);
}
//+------------------------------------------------------------------+

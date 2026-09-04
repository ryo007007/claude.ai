//+------------------------------------------------------------------+
//|                                              RSI_Trendlines.mq5  |
//|  RSIサブウィンドウにトレンドラインを引き、ブレイクでサイン表示   |
//|  参考: GFF系 RSI Trendlines（MT4 RSI_Trendlines 相当）            |
//+------------------------------------------------------------------+
#property copyright "RSI Trendlines for MT5"
#property version   "1.10"
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 4
#property indicator_plots   3

#property indicator_label1  "RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Buy"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2

#property indicator_label3  "Sell"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2

#property indicator_level1 50.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

//---------------- 入力 ----------------
input int    InpRSIPeriod        = 14;           // RSI期間
input int    InpTrendlinesPeriod = 5;            // トレンドライン用スイング間隔（大きいほどサイン減・精度↑）
input int    InpMaxLines         = 8;            // 同時に残すライン本数（高値側・安値側それぞれ）
input color  InpDownLineColor    = clrLime;      // 下降トレンドライン色（高値同士）
input color  InpUpLineColor      = clrRed;       // 上昇トレンドライン色（安値同士）
input int    InpLineWidth        = 1;            // ライン幅
input bool   InpShowPivotDots    = true;         // スイング点を点で表示
input color  InpPivotHighColor   = clrRed;       // 高値スイング点
input color  InpPivotLowColor    = clrLime;      // 安値スイング点
input bool   InpArrowsOnMain     = true;         // メインチャートにも矢印を出す
input bool   InpAlert            = true;         // アラート
input bool   InpPush             = false;        // プッシュ通知
input bool   InpEmail            = false;        // メール

//---------------- バッファ ----------------
double RSIBuffer[];
double BuyBuffer[];
double SellBuffer[];
double DummyColor[];   // 予備

int    g_hRSI = INVALID_HANDLE;
string g_prefix;
int    g_subwin = -1;
datetime g_lastBuyAlert = 0;
datetime g_lastSellAlert = 0;

#define OBJ_LINE_DN "RSITL_DN_"
#define OBJ_LINE_UP "RSITL_UP_"
#define OBJ_DOT_H   "RSITL_DH_"
#define OBJ_DOT_L   "RSITL_DL_"
#define OBJ_MAIN_BUY  "RSITL_MB_"
#define OBJ_MAIN_SELL "RSITL_MS_"

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, RSIBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, BuyBuffer,  INDICATOR_DATA);
   SetIndexBuffer(2, SellBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, DummyColor, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 234);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("RSI_Trendlines(%d,%d)", InpRSIPeriod, InpTrendlinesPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   g_hRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(g_hRSI == INVALID_HANDLE)
     {
      Print("iRSI failed");
      return(INIT_FAILED);
     }

   g_prefix = StringFormat("RSITL_%d_", ChartID());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hRSI != INVALID_HANDLE)
      IndicatorRelease(g_hRSI);
   DeleteAllOurObjects();
  }

//+------------------------------------------------------------------+
void DeleteAllOurObjects()
  {
   ObjectsDeleteAll(0, g_prefix);
   ObjectsDeleteAll(0, OBJ_LINE_DN);
   ObjectsDeleteAll(0, OBJ_LINE_UP);
   ObjectsDeleteAll(0, OBJ_DOT_H);
   ObjectsDeleteAll(0, OBJ_DOT_L);
   ObjectsDeleteAll(0, OBJ_MAIN_BUY);
   ObjectsDeleteAll(0, OBJ_MAIN_SELL);
  }

//+------------------------------------------------------------------+
int ResolveSubWindow()
  {
   int w = ChartWindowFind(0, StringFormat("RSI_Trendlines(%d,%d)", InpRSIPeriod, InpTrendlinesPeriod));
   if(w < 0)
      w = ChartWindowFind(0, "RSI_Trendlines");
   if(w < 0)
     {
      // 最後のサブウィンドウを仮採用
      int total = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
      if(total > 1)
         w = total - 1;
     }
   return(w);
  }

//+------------------------------------------------------------------+
bool IsPivotHigh(const double &buf[], const int i, const int strength, const int total)
  {
   // series配列: i=0 が最新。確定足のみ扱う前提で i>=strength
   if(i < strength || i + strength >= total)
      return(false);
   for(int k = 1; k <= strength; k++)
     {
      if(buf[i] <= buf[i - k] || buf[i] <= buf[i + k])
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
bool IsPivotLow(const double &buf[], const int i, const int strength, const int total)
  {
   if(i < strength || i + strength >= total)
      return(false);
   for(int k = 1; k <= strength; k++)
     {
      if(buf[i] >= buf[i - k] || buf[i] >= buf[i + k])
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
double LineValueAt(const datetime t1, const double v1,
                   const datetime t2, const double v2,
                   const datetime t)
  {
   if(t2 == t1)
      return(v2);
   double r = (double)(t - t1) / (double)(t2 - t1);
   return(v1 + (v2 - v1) * r);
  }

//+------------------------------------------------------------------+
void DrawTrendObject(const string name, const int subwin,
                     const datetime t1, const double v1,
                     const datetime t2, const double v2,
                     const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, subwin, t1, v1, t2, v2);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, v1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, v2);
     }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpLineWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void DrawDot(const string name, const int subwin,
             const datetime t, const double v, const color clr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, subwin, t, v);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0, name, OBJPROP_PRICE, v);
     }
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159); // 丸
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
void DrawMainArrow(const string name, const datetime t, const double price,
                   const bool isBuy)
  {
   if(!InpArrowsOnMain)
      return;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   else
     {
      ObjectSetInteger(0, name, OBJPROP_TIME, t);
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
     }
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpRSIPeriod + InpTrendlinesPeriod * 2 + 5)
      return(0);

   // time[] は非series（0=最古）。RSIバッファも同じ並びに合わせる
   ArraySetAsSeries(RSIBuffer, false);
   ArraySetAsSeries(BuyBuffer, false);
   ArraySetAsSeries(SellBuffer, false);

   if(CopyBuffer(g_hRSI, 0, 0, rates_total, RSIBuffer) < rates_total)
      return(prev_calculated);

   int start = (prev_calculated > 1) ? prev_calculated - 2 : 0;
   for(int i = start; i < rates_total; i++)
     {
      BuyBuffer[i]  = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;
     }

   //--- スイング抽出（非series: 大きいindexが新しい）
   int strength = InpTrendlinesPeriod;
   if(strength < 2)
      strength = 2;

   int highIdx[];
   int lowIdx[];
   ArrayResize(highIdx, 0);
   ArrayResize(lowIdx, 0);

   // 確定足のみ: 最新の形成中バー rates_total-1 はピボットに使わない
   int last = rates_total - 2;
   for(int i = strength; i <= last - strength; i++)
     {
      // 手動ピボット（非series用）
      bool isH = true;
      bool isL = true;
      for(int k = 1; k <= strength; k++)
        {
         if(RSIBuffer[i] <= RSIBuffer[i - k] || RSIBuffer[i] <= RSIBuffer[i + k])
            isH = false;
         if(RSIBuffer[i] >= RSIBuffer[i - k] || RSIBuffer[i] >= RSIBuffer[i + k])
            isL = false;
        }
      if(isH)
        {
         int n = ArraySize(highIdx);
         ArrayResize(highIdx, n + 1);
         highIdx[n] = i;
        }
      if(isL)
        {
         int n = ArraySize(lowIdx);
         ArrayResize(lowIdx, n + 1);
         lowIdx[n] = i;
        }
     }

   g_subwin = ResolveSubWindow();
   if(g_subwin < 0)
      g_subwin = 1;

   // 古いオブジェクトを消して描き直す（点数は少ないので負荷は小さい）
   ObjectsDeleteAll(0, OBJ_LINE_DN);
   ObjectsDeleteAll(0, OBJ_LINE_UP);
   ObjectsDeleteAll(0, OBJ_DOT_H);
   ObjectsDeleteAll(0, OBJ_DOT_L);

   int hCount = ArraySize(highIdx);
   int lCount = ArraySize(lowIdx);

   // 直近 InpMaxLines 本だけ使用（配列末尾が新しい）
   int hStart = MathMax(0, hCount - InpMaxLines - 1);
   int lStart = MathMax(0, lCount - InpMaxLines - 1);

   //--- 下降ライン: 連続する高値スイングを結ぶ
   for(int n = hStart; n < hCount - 1; n++)
     {
      int i1 = highIdx[n];
      int i2 = highIdx[n + 1];
      string name = OBJ_LINE_DN + IntegerToString(n);
      DrawTrendObject(name, g_subwin,
                      time[i1], RSIBuffer[i1],
                      time[i2], RSIBuffer[i2],
                      InpDownLineColor);
      if(InpShowPivotDots)
        {
         DrawDot(OBJ_DOT_H + IntegerToString(i1), g_subwin, time[i1], RSIBuffer[i1], InpPivotHighColor);
         DrawDot(OBJ_DOT_H + IntegerToString(i2), g_subwin, time[i2], RSIBuffer[i2], InpPivotHighColor);
        }
     }

   //--- 上昇ライン: 連続する安値スイングを結ぶ
   for(int n = lStart; n < lCount - 1; n++)
     {
      int i1 = lowIdx[n];
      int i2 = lowIdx[n + 1];
      string name = OBJ_LINE_UP + IntegerToString(n);
      DrawTrendObject(name, g_subwin,
                      time[i1], RSIBuffer[i1],
                      time[i2], RSIBuffer[i2],
                      InpUpLineColor);
      if(InpShowPivotDots)
        {
         DrawDot(OBJ_DOT_L + IntegerToString(i1), g_subwin, time[i1], RSIBuffer[i1], InpPivotLowColor);
         DrawDot(OBJ_DOT_L + IntegerToString(i2), g_subwin, time[i2], RSIBuffer[i2], InpPivotLowColor);
        }
     }

   //--- ブレイク判定: 直近の下降線・上昇線のみ
   int sigBar = rates_total - 1; // 最新
   if(sigBar < 2)
      return(rates_total);

   // 下降トレンドライン（高値）のブレイク上抜け → 買い
   if(hCount >= 2)
     {
      int i1 = highIdx[hCount - 2];
      int i2 = highIdx[hCount - 1];
      double lineNow  = LineValueAt(time[i1], RSIBuffer[i1], time[i2], RSIBuffer[i2], time[sigBar]);
      double linePrev = LineValueAt(time[i1], RSIBuffer[i1], time[i2], RSIBuffer[i2], time[sigBar - 1]);
      // 上抜け
      if(RSIBuffer[sigBar - 1] <= linePrev && RSIBuffer[sigBar] > lineNow)
        {
         BuyBuffer[sigBar] = RSIBuffer[sigBar];
         DrawMainArrow(OBJ_MAIN_BUY + TimeToString(time[sigBar]), time[sigBar],
                       low[sigBar] - 10 * _Point, true);
         if(InpAlert && time[sigBar] != g_lastBuyAlert)
           {
            g_lastBuyAlert = time[sigBar];
            string msg = _Symbol + " RSI TL Break BUY";
            if(InpAlert) Alert(msg);
            if(InpPush)  SendNotification(msg);
            if(InpEmail) SendMail("RSI Trendlines", msg);
           }
        }
     }

   // 上昇トレンドライン（安値）のブレイク下抜け → 売り
   if(lCount >= 2)
     {
      int i1 = lowIdx[lCount - 2];
      int i2 = lowIdx[lCount - 1];
      double lineNow  = LineValueAt(time[i1], RSIBuffer[i1], time[i2], RSIBuffer[i2], time[sigBar]);
      double linePrev = LineValueAt(time[i1], RSIBuffer[i1], time[i2], RSIBuffer[i2], time[sigBar - 1]);
      if(RSIBuffer[sigBar - 1] >= linePrev && RSIBuffer[sigBar] < lineNow)
        {
         SellBuffer[sigBar] = RSIBuffer[sigBar];
         DrawMainArrow(OBJ_MAIN_SELL + TimeToString(time[sigBar]), time[sigBar],
                       high[sigBar] + 10 * _Point, false);
         if(InpAlert && time[sigBar] != g_lastSellAlert)
           {
            g_lastSellAlert = time[sigBar];
            string msg = _Symbol + " RSI TL Break SELL";
            if(InpAlert) Alert(msg);
            if(InpPush)  SendNotification(msg);
            if(InpEmail) SendMail("RSI Trendlines", msg);
           }
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+

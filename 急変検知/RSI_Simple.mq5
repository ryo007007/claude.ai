//+------------------------------------------------------------------+
//|                                                    RSI_Simple.mq5 |
//|  普通のRSIをサブウィンドウに表示するだけ                            |
//+------------------------------------------------------------------+
#property copyright "RSI Simple"
#property version   "1.00"
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_level1 70.0
#property indicator_level2 50.0
#property indicator_level3 30.0
#property indicator_levelcolor clrDimGray
#property indicator_levelstyle STYLE_DOT

input int    InpRSIPeriod = 14;            // RSI期間
input color  InpRSIColor  = clrDodgerBlue; // RSI線の色
input int    InpRSIWidth  = 2;             // RSI線の太さ
input double InpLevelUp   = 70.0;          // 上限レベル
input double InpLevelMid  = 50.0;          // 中央レベル
input double InpLevelDn   = 30.0;          // 下限レベル

double RSIBuffer[];
int    g_hRSI = INVALID_HANDLE;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, RSIBuffer, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpRSIColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpRSIWidth);

   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, InpLevelUp);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, InpLevelMid);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, InpLevelDn);
   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("RSI_Simple(%d)", InpRSIPeriod));
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   g_hRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(g_hRSI == INVALID_HANDLE)
     {
      Print("iRSI failed err=", GetLastError());
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_hRSI != INVALID_HANDLE)
      IndicatorRelease(g_hRSI);
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
   if(rates_total < InpRSIPeriod + 2)
      return(0);

   ArraySetAsSeries(RSIBuffer, false);

   if(CopyBuffer(g_hRSI, 0, 0, rates_total, RSIBuffer) <= 0)
      return(prev_calculated);

   return(rates_total);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                        CCompression_Demo.mq5      |
//|  CCompressionモジュールの動作確認用デモインジケーター             |
//|  現在チャートの通貨ペアを D1/H4/M15/M5/M1 の5つの時間足で同時に   |
//|  監視し、左上にスコア・状態・Delta・Ageを表示する。                |
//+------------------------------------------------------------------+
#property copyright "CCompression demo"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include "CCompression_Multi.mqh"

ENUM_TIMEFRAMES g_demoTFs[] = {PERIOD_D1, PERIOD_H4, PERIOD_M15, PERIOD_M5, PERIOD_M1};

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!CCOMP_MultiInit(_Symbol, g_demoTFs, ArraySize(g_demoTFs)))
      Print("CCompression_Demo: 一部時間足の初期化に失敗した可能性があります");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   Comment("");
   CCOMP_MultiDeinit();
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                 const datetime &time[], const double &open[], const double &high[],
                 const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
  {
   CCOMP_MultiUpdate();

   string report = StringFormat("=== CCompression [%s] ===\n", _Symbol);
   for(int i = 0; i < ArraySize(g_demoTFs); i++)
     {
      CCOMP_Instance inst;
      if(!CCOMP_MultiGet(g_demoTFs[i], inst) || !inst.ready)
        {
         report += StringFormat("%-6s 準備中...\n", EnumToString(g_demoTFs[i]));
         continue;
        }

      report += StringFormat("%-6s %-20s Score=%d/8 (ATR%d BB%d Rng%d ADX%d) Delta=%+d Age=%d  ATR%%=%.3f BBWidth%%=%.3f Range20%%=%.3f ADX=%.1f\n",
         EnumToString(g_demoTFs[i]),
         CCOMP_StateText(inst.state),
         inst.score, inst.atrScore, inst.bbScore, inst.rangeScore, inst.adxScore,
         inst.delta, inst.age,
         inst.atrPct, inst.bbWidthPct, inst.range20Pct, inst.adxValue);
     }

   int compressedCount = CCOMP_MultiCountCompressed(CCOMP_STRONG_COMPRESSION);
   if(compressedCount >= 2)
      report += StringFormat("\n⚠ %d個の時間足が同時にSTRONG/TIGHT COMPRESSION状態です", compressedCount);

   Comment(report);
   return(rates_total);
  }
//+------------------------------------------------------------------+

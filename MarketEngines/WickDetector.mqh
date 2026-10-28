//+------------------------------------------------------------------+
//|                                                  WickDetector.mqh |
//|  髭（WICK）専用検知エンジン                                        |
//+------------------------------------------------------------------+
#property copyright "Wick Detector"
#property version   "1.00"

//--- 髭検知結果構造体
struct WICK_Info
{
   bool     isWick;       // 髭と判定されたか
   bool     isUpper;      // 上髭
   bool     isLower;      // 下髭
   double   wickRatio;    // の割合 (0.0〜1.0)
   double   totalRange;   // 値幅 (High-Low)
   double   medianRange;  // 基準値幅 (中央値)
   double   multiplier;   // 倍率 (totalRange / medianRange)
};

//+------------------------------------------------------------------+
//| 髭検知メイン関数                                                   |
//| shift: 判定対象の足（0=現在足, 1=1本前, 2=2本前...）               |
//+------------------------------------------------------------------+
bool WICK_Check(const string symbol, const ENUM_TIMEFRAMES tf, const int shift,
                const double rangeMultiplier, const double minWickRatio,
                WICK_Info &info)
{
   //--- 初期化
   info.isWick   = false;
   info.isUpper  = false;
   info.isLower  = false;
   info.wickRatio    = 0.0;
   info.totalRange   = 0.0;
   info.medianRange  = 0.0;
   info.multiplier   = 0.0;

   //--- 基準値幅の計算（判定足の次の足から20本分）
   //    shift=1（1本前）の場合、shift+1=2（2本前）から20本を取得
   double ranges[20];
   int copied = 0;
   for(int i = 0; i < 20; i++)
     {
      double h = iHigh(symbol, tf, shift + 1 + i);
      double l = iLow(symbol, tf, shift + 1 + i);
      if(h < 0 || l < 0 || h <= l) continue;
      ranges[copied] = h - l;
      copied++;
     }
   if(copied < 20) return false;

   ArraySort(ranges);
   info.medianRange = ranges[9]; // 中央値
   if(info.medianRange <= 0.0) return false;

   //--- 判定対象足（shift本前）の取得
   double open  = iOpen(symbol, tf, shift);
   double high  = iHigh(symbol, tf, shift);
   double low   = iLow(symbol, tf, shift);
   double close = iClose(symbol, tf, shift);
   if(open <= 0 || high <= 0 || low <= 0 || close <= 0) return false;

   info.totalRange = high - low;
   if(info.totalRange <= 0.0) return false;

   //--- 条件1: 値幅が基準の倍以上か
   info.multiplier = info.totalRange / info.medianRange;
   if(info.multiplier < rangeMultiplier) return false;

   //--- 髭の計算
   double bodyTop    = MathMax(open, close);
   double bodyBottom = MathMin(open, close);
   double upperWick  = high - bodyTop;
   double lowerWick  = bodyBottom - low;

   //--- 条件2: 髭割合が閾値以上か
   if(upperWick >= lowerWick)
     {
      info.wickRatio = upperWick / info.totalRange;
      if(info.wickRatio < minWickRatio) return false;
      info.isUpper = true;
     }
   else
     {
      info.wickRatio = lowerWick / info.totalRange;
      if(info.wickRatio < minWickRatio) return false;
      info.isLower = true;
     }

   info.isWick = true;
   return true;
}

//+------------------------------------------------------------------+
//| ログ用特徴文字列                                                   |
//+------------------------------------------------------------------+
string WICK_Feat(const WICK_Info &info)
{
   return StringFormat("dir=%s;wick_ratio=%.2f;range_mult=%.1f;median=%.5f;total=%.5f",
                       info.isUpper ? "upper" : "lower",
                       info.wickRatio, info.multiplier,
                       info.medianRange, info.totalRange);
}
//+------------------------------------------------------------------+
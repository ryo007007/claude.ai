//+------------------------------------------------------------------+
//|                                                  WickDetector.mqh |
//|  髭（WICK）専用検知エンジン                                        |
//|  ・基準: 直前20本の値幅(High-Low)の中央値                          |
//|  ・条件: 値幅 >= 中央値 × 倍率  かつ  髭割合 >= 閾値               |
//+------------------------------------------------------------------+
#property copyright "Wick Detector"
#property version   "1.00"

//--- 髭検知結果構造体
struct WICK_Info
{
   bool     isWick;       // と判定されたか
   bool     isUpper;      // 上髭
   bool     isLower;      // 下髭
   double   wickRatio;    // 髭の割合 (0.0?1.0)
   double   totalRange;   // 値幅 (High-Low)
   double   medianRange;  // 基準値幅 (中央値)
   double   multiplier;   // 倍率 (totalRange / medianRange)
};

//+------------------------------------------------------------------+
//| 髭検知メイン関数                                                   |
//| 判定対象: 1本前の確定足                                            |
//| 基準データ: 2本前?21本前の20足                                    |
//+------------------------------------------------------------------+
bool WICK_Check(const string symbol, const ENUM_TIMEFRAMES tf,
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

   //--- 基準値幅の計算（2本前?21本前の20足の中央値）
   double ranges[20];
   int copied = 0;
   for(int i = 0; i < 20; i++)
     {
      double h = iHigh(symbol, tf, i + 2);
      double l = iLow(symbol, tf, i + 2);
      if(h < 0 || l < 0 || h <= l) continue; // データ不正
      ranges[copied] = h - l;
      copied++;
     }
   if(copied < 20) return false; // データ不足

   ArraySort(ranges);
   info.medianRange = ranges[9]; // 20本の中央値（10番目）
   if(info.medianRange <= 0.0) return false;

   //--- 判定対象足（1本前）の取得
   double open  = iOpen(symbol, tf, 1);
   double high  = iHigh(symbol, tf, 1);
   double low   = iLow(symbol, tf, 1);
   double close = iClose(symbol, tf, 1);
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
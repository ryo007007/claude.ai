//+------------------------------------------------------------------+
//| EMAAlignmentEngine.mqh                                           |
//| H4/H1/M15 200EMA + 圧縮の押し目 / 戻り判定 (緩和版)               |
//|                                                                    |
//|  v2.1 変更点 (v2.0→v2.1):                                         |
//|  ・トレンド条件緩和: 3期間中2つ以上が同方向でOK                     |
//|  ・距離条件緩和: 固定2.0倍に変更 (v1.53の1.0→2.0)                  |
//|  ・アライメント条件緩和: EMA差がATR×1.5以内ならOK                  |
//|  ・ゾーン条件緩和: 深さスコア20以上で許容                          |
//|  ・v1.53互換モード: InpEMAAlignStrict=falseでv1.53同等の検知率      |
//+------------------------------------------------------------------+
#property copyright "EMA Alignment Engine v2.1"
#property version   "2.10"

struct EMA_ALIGN_Result
  {
   bool   ready;
   int    dir;           // 1=買い, -1=売り, 0=なし
   double emaH4;
   double emaH1;
   double emaM15;
   double emaD1;
   double price;
   int    slopeH4;
   int    slopeH4Med;
   int    slopeH4Long;
   int    slopeH1;
   int    slopeM15;
   int    slopeD1;
   int    pricePos;
   int    pricePosH4;
   int    pricePosM15;
   double atrH4;
   double distH4;
   double distH1;
   int    depthScore;
   int    trendStrength;
   int    alignmentScore;
   int    divergence;
   int    eqs;
   double dynamicATRMult;
   string zoneLabel;
  };

struct EMA_AlignHandle
  {
   string symbol;
   int    hH4;
   int    hH1;
   int    hM15;
   int    hD1;
   int    hATRH4;
  };

EMA_AlignHandle g_emaHandles[];
int             g_emaHandlePeriod = 200;

//+------------------------------------------------------------------+
void EMA_AlignRelease()
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
     {
      if(g_emaHandles[i].hH4 > 0)   IndicatorRelease(g_emaHandles[i].hH4);
      if(g_emaHandles[i].hH1 > 0)   IndicatorRelease(g_emaHandles[i].hH1);
      if(g_emaHandles[i].hM15 > 0)  IndicatorRelease(g_emaHandles[i].hM15);
      if(g_emaHandles[i].hD1 > 0)   IndicatorRelease(g_emaHandles[i].hD1);
      if(g_emaHandles[i].hATRH4 > 0) IndicatorRelease(g_emaHandles[i].hATRH4);
     }
   ArrayResize(g_emaHandles, 0);
  }

//+------------------------------------------------------------------+
bool EMA_GetValue(const int handle, const int shift, double &out)
  {
   if(handle <= 0) return false;
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   out = buf[0];
   return true;
  }

//+------------------------------------------------------------------+
int EMA_AlignHandleIndex(const string symbol, const int emaPeriod,
                         const bool useD1, const bool useH4, const bool useM15)
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
      if(g_emaHandles[i].symbol == symbol)
        {
         if(useH4 && g_emaHandles[i].hH4 <= 0)
            g_emaHandles[i].hH4 = iMA(symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(useH4 && g_emaHandles[i].hATRH4 <= 0)
            g_emaHandles[i].hATRH4 = iATR(symbol, PERIOD_H4, 14);
         if(useM15 && g_emaHandles[i].hM15 <= 0)
            g_emaHandles[i].hM15 = iMA(symbol, PERIOD_M15, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(useD1 && g_emaHandles[i].hD1 <= 0)
            g_emaHandles[i].hD1 = iMA(symbol, PERIOD_D1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         return i;
        }

   int idx = ArraySize(g_emaHandles);
   ArrayResize(g_emaHandles, idx + 1);
   g_emaHandles[idx].symbol  = symbol;
   g_emaHandles[idx].hH4     = useH4  ? iMA(symbol, PERIOD_H4,  emaPeriod, 0, MODE_EMA, PRICE_CLOSE) : 0;
   g_emaHandles[idx].hH1     = iMA(symbol, PERIOD_H1,  emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_emaHandles[idx].hM15    = useM15 ? iMA(symbol, PERIOD_M15, emaPeriod, 0, MODE_EMA, PRICE_CLOSE) : 0;
   g_emaHandles[idx].hD1     = useD1  ? iMA(symbol, PERIOD_D1,  emaPeriod, 0, MODE_EMA, PRICE_CLOSE) : 0;
   g_emaHandles[idx].hATRH4  = useH4  ? iATR(symbol, PERIOD_H4, 14) : 0;
   g_emaHandlePeriod = emaPeriod;
   return idx;
  }

//+------------------------------------------------------------------+
int EMA_SlopeDir(const double nowVal, const double oldVal, const double eps)
  {
   if((nowVal - oldVal) > eps) return 1;
   if((oldVal - nowVal) > eps) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| トレンド強度スコア (0-100)                                         |
//+------------------------------------------------------------------+
int EMA_TrendStrength(const int slopeShort, const int slopeMed, const int slopeLong)
  {
   double score = 0.0;
   if(slopeShort != 0) score += 50.0;
   if(slopeMed != 0 && slopeMed == slopeShort) score += 30.0;
   else if(slopeMed != 0) score += 15.0;
   if(slopeLong != 0 && slopeLong == slopeShort) score += 20.0;
   else if(slopeLong != 0) score += 10.0;
   return (int)score;
  }

//+------------------------------------------------------------------+
//| 深さスコア計算 (0-100)                                             |
//+------------------------------------------------------------------+
int EMA_DepthScore(const double price, const double emaInner, const double emaOuter)
  {
   double zoneWidth = MathAbs(emaOuter - emaInner);
   if(zoneWidth <= 0.0) return 50;
   double distFromInner = MathAbs(price - emaInner);
   double distFromOuter = MathAbs(price - emaOuter);
   double ratio = distFromInner / zoneWidth;
   if(distFromOuter < distFromInner) ratio = 1.0 - ratio;
   return (int)MathRound(MathMax(0.0, MathMin(1.0, ratio)) * 100.0);
  }

//+------------------------------------------------------------------+
//| ダイバージェンス検知                                               |
//+------------------------------------------------------------------+
int EMA_Divergence(const string symbol, const ENUM_TIMEFRAMES tf,
                    const double emaNow, const double emaOld, const int lookback)
  {
   double priceLowNow  = iLow(symbol, tf, 1);
   double priceLowOld  = iLow(symbol, tf, lookback);
   double priceHighNow = iHigh(symbol, tf, 1);
   double priceHighOld = iHigh(symbol, tf, lookback);
   if(priceLowNow <= 0.0 || priceLowOld <= 0.0) return 0;
   if(priceHighNow <= 0.0 || priceHighOld <= 0.0) return 0;
   bool priceLowerLow  = (priceLowNow < priceLowOld);
   bool emaNotLower    = (emaNow >= emaOld);
   if(priceLowerLow && emaNotLower) return 1;
   bool priceHigherHigh = (priceHighNow > priceHighOld);
   bool emaNotHigher    = (emaNow <= emaOld);
   if(priceHigherHigh && emaNotHigher) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| 3時間足アライメントスコア (0-100)                                   |
//+------------------------------------------------------------------+
int EMA_AlignmentScore(const int slopeH4, const int slopeH1, const int slopeM15,
                        const bool useH4, const bool useM15)
  {
   int match = 0;
   int total = 1;
   if(useH4)
     {
      total++;
      if(slopeH4 != 0 && slopeH4 == slopeH1) match++;
     }
   if(useM15)
     {
      total++;
      if(slopeM15 != 0 && slopeM15 == slopeH1) match++;
     }
   if(total <= 1) return 50;
   return (match * 100) / (total - 1);
  }

//+------------------------------------------------------------------+
//| エントリー品質スコア (EQS) 0-100                                   |
//+------------------------------------------------------------------+
int EMA_EntryQualityScore(const int trendStr, const int depth,
                           const int align, const int div)
  {
   double score = trendStr * 0.40 + depth * 0.30 + align * 0.20;
   if(div != 0) score += 10.0;
   return (int)MathMin(100.0, score);
  }

//+------------------------------------------------------------------+
//| ゾーンラベル生成                                                     |
//+------------------------------------------------------------------+
string EMA_ZoneLabel(const int dir, const int depthScore)
  {
   if(dir == 0) return "";
   if(dir > 0)
     {
      if(depthScore >= 70) return "深押し";
      if(depthScore >= 40) return "押し";
      return "浅押し";
     }
   else
     {
      if(depthScore >= 70) return "深戻り";
      if(depthScore >= 40) return "戻り";
      return "浅戻り";
     }
  }

//+------------------------------------------------------------------+
//| v2.1 緩和トレンド判定                                               |
//| 3期間中2つ以上が同方向でOK (0は無視)                               |
//+------------------------------------------------------------------+
bool EMA_RelaxedTrend(const int slopeShort, const int slopeMed, const int slopeLong)
  {
   if(slopeShort == 0) return false;
   int match = 1; // slopeShortは必須で非ゼロ
   if(slopeMed == slopeShort) match++;
   if(slopeLong == slopeShort) match++;
   return (match >= 2); // 2つ以上が同方向
  }

//+------------------------------------------------------------------+
//| v2.1 緩和アライメント判定                                           |
//| H1とH4のEMA差がATR×1.5以内ならOK (完全な逆転はNG)                  |
//+------------------------------------------------------------------+
bool EMA_RelaxedAlign(const double h1Now, const double h4Now, const double atrH4,
                       const int dir)
  {
   if(atrH4 <= 0.0) return true;
   double emaDiff = h1Now - h4Now;
   double threshold = atrH4 * 1.5;
   if(dir > 0) return (emaDiff > -threshold); // H1がH4より少し下でも許容
   if(dir < 0) return (emaDiff < threshold);  // H1がH4より少し上でも許容
   return false;
  }

//+------------------------------------------------------------------+
//| 本体：H4/H1/M15(+D1) 200EMA の向きと価格位置を判定                 |
//+------------------------------------------------------------------+
bool EMA_AlignCompute(const string symbol, const int emaPeriod,
                       const int slopeBarsShort, const int slopeBarsMed, const int slopeBarsLong,
                       const bool useD1, const bool useH4, const bool useM15,
                       EMA_ALIGN_Result &r)
  {
   r.ready = false;
   r.dir = 0;
   r.emaH4 = 0.0; r.emaH1 = 0.0; r.emaM15 = 0.0; r.emaD1 = 0.0;
   r.price = 0.0;
   r.slopeH4 = 0; r.slopeH4Med = 0; r.slopeH4Long = 0;
   r.slopeH1 = 0; r.slopeM15 = 0; r.slopeD1 = 0;
   r.pricePos = 0; r.pricePosH4 = 0; r.pricePosM15 = 0;
   r.atrH4 = 0.0; r.distH4 = 0.0; r.distH1 = 0.0;
   r.depthScore = 0; r.trendStrength = 0; r.alignmentScore = 0;
   r.divergence = 0; r.eqs = 0; r.dynamicATRMult = 2.0; // v2.1: 固定2.0
   r.zoneLabel = "";

   int hi = EMA_AlignHandleIndex(symbol, emaPeriod, useD1, useH4, useM15);
   if(hi < 0) return false;

   int shiftNow  = 1;
   int shiftShort = 1 + MathMax(1, slopeBarsShort);
   int shiftMed   = 1 + MathMax(1, slopeBarsMed);
   int shiftLong  = 1 + MathMax(1, slopeBarsLong);

   double h4Now = 0.0, h4Short = 0.0, h4Med = 0.0, h4Long = 0.0;
   double h1Now = 0.0, h1Short = 0.0;
   double m15Now = 0.0, m15Short = 0.0;
   double d1Now = 0.0, d1Short = 0.0;
   double atrH4 = 0.0;

   if(useH4)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftNow, h4Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftShort, h4Short)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftMed, h4Med)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftLong, h4Long)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hATRH4, shiftNow, atrH4)) return false;
     }
   if(!EMA_GetValue(g_emaHandles[hi].hH1, shiftNow, h1Now)) return false;
   if(!EMA_GetValue(g_emaHandles[hi].hH1, shiftShort, h1Short)) return false;

   if(useM15)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hM15, shiftNow, m15Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hM15, shiftShort, m15Short)) return false;
     }
   if(useD1)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hD1, shiftNow, d1Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hD1, shiftShort, d1Short)) return false;
     }

   double close1 = iClose(symbol, PERIOD_H1, 1);
   if(close1 <= 0.0) return false;

   r.emaH4  = h4Now;
   r.emaH1  = h1Now;
   r.emaM15 = m15Now;
   r.emaD1  = d1Now;
   r.price  = close1;
   r.atrH4  = atrH4;
   r.distH4 = useH4 ? MathAbs(close1 - h4Now) : 0.0;
   r.distH1 = MathAbs(close1 - h1Now);

   double epsH4  = h4Now * 0.0001;
   double epsH1  = h1Now * 0.0001;
   double epsM15 = m15Now * 0.0001;
   double epsD1  = d1Now * 0.0001;

   r.slopeH4     = useH4 ? EMA_SlopeDir(h4Now, h4Short, epsH4) : 0;
   r.slopeH4Med  = useH4 ? EMA_SlopeDir(h4Now, h4Med, epsH4) : 0;
   r.slopeH4Long = useH4 ? EMA_SlopeDir(h4Now, h4Long, epsH4) : 0;
   r.slopeH1     = EMA_SlopeDir(h1Now, h1Short, epsH1);
   r.slopeM15    = useM15 ? EMA_SlopeDir(m15Now, m15Short, epsM15) : 0;
   r.slopeD1     = useD1 ? EMA_SlopeDir(d1Now, d1Short, epsD1) : 0;

   r.pricePos    = (close1 > h1Now ? 1 : (close1 < h1Now ? -1 : 0));
   r.pricePosH4  = useH4 ? (close1 > h4Now ? 1 : (close1 < h4Now ? -1 : 0)) : 0;
   r.pricePosM15 = useM15 ? (close1 > m15Now ? 1 : (close1 < m15Now ? -1 : 0)) : 0;

   // --- 日足フィルター ---
   if(useD1)
     {
      int trendSlope = useH4 ? r.slopeH4 : r.slopeH1;
      if(trendSlope != 0 && r.slopeD1 != 0 && r.slopeD1 != trendSlope)
        {
         r.ready = true;
         return true;
        }
     }

   // --- H4を使わない場合のフォールバック ---
   if(!useH4)
     {
      if(r.slopeH1 > 0 && r.pricePos < 0)
        {
         r.dir = 1;
         r.depthScore = EMA_DepthScore(close1, h1Now, h1Now * 0.999);
        }
      else if(r.slopeH1 < 0 && r.pricePos > 0)
        {
         r.dir = -1;
         r.depthScore = EMA_DepthScore(close1, h1Now, h1Now * 1.001);
        }
      r.trendStrength = EMA_TrendStrength(r.slopeH1, r.slopeH1, 0);
      r.alignmentScore = 50;
      r.eqs = EMA_EntryQualityScore(r.trendStrength, r.depthScore, r.alignmentScore, 0);
      r.ready = true;
      return true;
     }

   // --- v2.1 緩和条件 ---
   // 買い（押し目）: 上向きチェックを追加
   bool buyTrend = (r.slopeH4 > 0) && EMA_RelaxedTrend(r.slopeH4, r.slopeH4Med, r.slopeH4Long);
   bool buyAlign = EMA_RelaxedAlign(h1Now, h4Now, atrH4, 1);
   bool buyZone  = (r.pricePosH4 >= 0 && r.pricePos <= 0); // v2.1: >= と <= で境界許容
   bool buyDist  = (atrH4 > 0.0 && r.distH4 < atrH4 * 2.0); // v2.1: 2.0倍に緩和

   // 売り（戻り）
   bool sellTrend = (r.slopeH4 < 0) && EMA_RelaxedTrend(r.slopeH4, r.slopeH4Med, r.slopeH4Long);
   bool sellAlign = EMA_RelaxedAlign(h1Now, h4Now, atrH4, -1);
   bool sellZone  = (r.pricePosH4 <= 0 && r.pricePos >= 0); // v2.1: 境界許容
   bool sellDist  = (atrH4 > 0.0 && r.distH4 < atrH4 * 2.0); // v2.1: 2.0倍に緩和

   if(buyTrend && buyAlign && buyZone && buyDist)
     {
      r.dir = 1;
      r.depthScore = EMA_DepthScore(close1, h4Now, h1Now);
     }
   else if(sellTrend && sellAlign && sellZone && sellDist)
     {
      r.dir = -1;
      r.depthScore = EMA_DepthScore(close1, h1Now, h4Now);
     }

   // --- スコア計算 ---
   r.trendStrength    = EMA_TrendStrength(r.slopeH4, r.slopeH4Med, r.slopeH4Long);
   r.alignmentScore   = EMA_AlignmentScore(r.slopeH4, r.slopeH1, r.slopeM15, useH4, useM15);
   r.divergence       = useH4 ? EMA_Divergence(symbol, PERIOD_H4, h4Now, h4Short, slopeBarsShort) : 0;
   r.eqs              = EMA_EntryQualityScore(r.trendStrength, r.depthScore, r.alignmentScore, r.divergence);
   r.zoneLabel        = EMA_ZoneLabel(r.dir, r.depthScore);

   r.ready = true;
   return true;
  }

//+------------------------------------------------------------------+
string EMA_AlignFeat(const EMA_ALIGN_Result &r)
  {
   return StringFormat("ema_dir=%d;depth=%d;trend=%d;align=%d;div=%d;eqs=%d;zone=%s;atrMult=%.2f;slopeH4=%d;slopeH4Med=%d;slopeH4Long=%d;slopeH1=%d;slopeM15=%d;slopeD1=%d;pricePos=%d;pricePosH4=%d;pricePosM15=%d;emaH4=%.5f;emaH1=%.5f;emaM15=%.5f;price=%.5f;atrH4=%.5f;distH4=%.5f",
                       r.dir, r.depthScore, r.trendStrength, r.alignmentScore, r.divergence, r.eqs, r.zoneLabel, r.dynamicATRMult,
                       r.slopeH4, r.slopeH4Med, r.slopeH4Long, r.slopeH1, r.slopeM15, r.slopeD1,
                       r.pricePos, r.pricePosH4, r.pricePosM15, r.emaH4, r.emaH1, r.emaM15, r.price, r.atrH4, r.distH4);
  }
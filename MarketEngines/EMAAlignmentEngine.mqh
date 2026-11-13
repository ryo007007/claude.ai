//| EMAAlignmentEngine.mqh                                           |
//| H4/H1 200EMA + 圧縮の押し目 / 戻り判定                            |
//| ・圧縮エンジンとは独立。判定のみを行う                            |
//| ・iMAハンドルは symbol ごとにキャッシュする                       |
//| ・v1.53：2期間スロープ + EMA並び + 押し目ゾーン + ATR距離          |
#property copyright "EMA Alignment Engine"
#property version   "1.53"

struct EMA_ALIGN_Result
  {
   bool   ready;      // 計算できたか
   int    dir;        // 1=買い条件, -1=売り条件, 0=なし
   double emaH4;      // H4 200EMA (確定足 shift=1)
   double emaH1;      // H1 200EMA (確定足 shift=1)
   double emaD1;      // D1 200EMA (確定足 shift=1, UseD1=falseなら0)
   double price;      // H1 終値 (確定足 shift=1)
   int    slopeH4;    // 1=上, -1=下, 0=横ばい (10本前比較)
   int    slopeH4Long;// 1=上, -1=下, 0=横ばい (30本前比較)
   int    slopeH1;
   int    slopeD1;
   int    pricePos;   // 1=価格はH1 EMAより上, -1=下
   int    pricePosH4; // 1=価格はH4 EMAより上, -1=下
   double atrH4;      // H4 ATR(14) 確定足 shift=1
   double distH4;     // 価格とH4 EMAの距離 (絶対値)
  };

struct EMA_AlignHandle
  {
   string symbol;
   int    hH4;
   int    hH1;
   int    hD1;
   int    hATRH4;
  };

EMA_AlignHandle g_emaHandles[];
int             g_emaHandlePeriod = 200;

//| ハンドル解放（OnDeinitから呼ぶ）                                  |
void EMA_AlignRelease()
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
     {
      if(g_emaHandles[i].hH4 > 0) IndicatorRelease(g_emaHandles[i].hH4);
      if(g_emaHandles[i].hH1 > 0) IndicatorRelease(g_emaHandles[i].hH1);
      if(g_emaHandles[i].hD1 > 0) IndicatorRelease(g_emaHandles[i].hD1);
      if(g_emaHandles[i].hATRH4 > 0) IndicatorRelease(g_emaHandles[i].hATRH4);
     }
   ArrayResize(g_emaHandles, 0);
  }

//| 1本のEMA値を取る                                                  |
bool EMA_GetValue(const int handle, const int shift, double &out)
  {
   if(handle <= 0) return false;
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
   out = buf[0];
   return true;
  }

//| symbol のハンドルを取得（なければ作る、後から日足ON対応）          |
int EMA_AlignHandleIndex(const string symbol, const int emaPeriod, const bool useD1, const bool useH4)
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
      if(g_emaHandles[i].symbol == symbol)
        {
         if(useH4 && g_emaHandles[i].hH4 <= 0)
            g_emaHandles[i].hH4 = iMA(symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(useH4 && g_emaHandles[i].hATRH4 <= 0)
            g_emaHandles[i].hATRH4 = iATR(symbol, PERIOD_H4, 14);
         if(useD1 && g_emaHandles[i].hD1 <= 0)
            g_emaHandles[i].hD1 = iMA(symbol, PERIOD_D1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
         return i;
        }

   int idx = ArraySize(g_emaHandles);
   ArrayResize(g_emaHandles, idx + 1);
   g_emaHandles[idx].symbol = symbol;
   g_emaHandles[idx].hH4 = useH4 ? iMA(symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE) : 0;
   g_emaHandles[idx].hH1 = iMA(symbol, PERIOD_H1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_emaHandles[idx].hD1 = useD1 ? iMA(symbol, PERIOD_D1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE) : 0;
   g_emaHandles[idx].hATRH4 = useH4 ? iATR(symbol, PERIOD_H4, 14) : 0;
   g_emaHandlePeriod = emaPeriod;
   return idx;
  }

//| 向き判定（横ばい帯つき）                                           |
int EMA_SlopeDir(const double nowVal, const double oldVal, const double eps)
  {
   if((nowVal - oldVal) > eps) return 1;
   if((oldVal - nowVal) > eps) return -1;
   return 0;
  }

//| 本体：H4/H1(+D1) 200EMA の向きと価格位置を判定                    |
//| ※ 確定足のみ使う。未確定足は見ない                                |
bool EMA_AlignCompute(const string symbol, const int emaPeriod, const int slopeBars, const bool useD1, const bool useH4, EMA_ALIGN_Result &r)
  {
   r.ready = false;
   r.dir = 0;
   r.emaH4 = 0.0; r.emaH1 = 0.0; r.emaD1 = 0.0; r.price = 0.0;
   r.slopeH4 = 0; r.slopeH4Long = 0; r.slopeH1 = 0; r.slopeD1 = 0;
   r.pricePos = 0; r.pricePosH4 = 0; r.atrH4 = 0.0; r.distH4 = 0.0;
   int hi = EMA_AlignHandleIndex(symbol, emaPeriod, useD1, useH4);
   if(hi < 0) return false;

   int shiftNow = 1;
   int shiftOld = 1 + MathMax(1, slopeBars);      // 例：SlopeBars=10 → 11
   int shiftOldLong = 1 + 30;                      // 長期確認用：31

   double h4Now = 0.0, h4Old = 0.0, h4OldLong = 0.0;
   double h1Now = 0.0, h1Old = 0.0, d1Now = 0.0, d1Old = 0.0;
   double atrH4 = 0.0;

   if(useH4)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftNow, h4Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftOld, h4Old)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftOldLong, h4OldLong)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hATRH4, shiftNow, atrH4)) return false;
     }
   if(!EMA_GetValue(g_emaHandles[hi].hH1, shiftNow, h1Now)) return false;
   if(!EMA_GetValue(g_emaHandles[hi].hH1, shiftOld, h1Old)) return false;

   if(useD1)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hD1, shiftNow, d1Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hD1, shiftOld, d1Old)) return false;
     }

   double close1 = iClose(symbol, PERIOD_H1, 1);
   if(close1 <= 0.0) return false;

   r.emaH4 = h4Now;
   r.emaH1 = h1Now;
   r.emaD1 = d1Now;
   r.price = close1;
   r.atrH4 = atrH4;
   r.distH4 = useH4 ? MathAbs(close1 - h4Now) : 0.0;

   // --- 向き判定：eps = 0.01% ---
   double epsH4 = h4Now * 0.0001;
   double epsH1 = h1Now * 0.0001;
   double epsD1 = d1Now * 0.0001;

   r.slopeH4 = useH4 ? EMA_SlopeDir(h4Now, h4Old, epsH4) : 0;
   r.slopeH4Long = useH4 ? EMA_SlopeDir(h4Now, h4OldLong, epsH4) : 0;
   r.slopeH1 = EMA_SlopeDir(h1Now, h1Old, epsH1);
   r.slopeD1 = useD1 ? EMA_SlopeDir(d1Now, d1Old, epsD1) : 0;

   r.pricePos = (close1 > h1Now ? 1 : (close1 < h1Now ? -1 : 0));
   r.pricePosH4 = useH4 ? (close1 > h4Now ? 1 : (close1 < h4Now ? -1 : 0)) : 0;
   r.ready = true;

   // 日足フィルター
   if(useD1)
     {
      int trendSlope = useH4 ? r.slopeH4 : r.slopeH1;
      if(trendSlope != 0 && r.slopeD1 != 0 && r.slopeD1 != trendSlope) return true;
     }

   // --- H4を使わない場合のフォールバック（今まで通り） ---
   if(!useH4)
     {
      if(r.slopeH1 > 0 && r.pricePos < 0)
         r.dir = 1;
      else if(r.slopeH1 < 0 && r.pricePos > 0)
         r.dir = -1;
      return true;
     }

   // --- v1.53 買い（押し目）4条件 ---
   // ① H4が上向き（10本前・30本前、両方）
   // ② EMAの並びが上昇（H1 200EMA ＞ H4 200EMA）
   // ③ 押し目ゾーン（H4 200EMA ＜ 価格 ＜ H1 200EMA）
   // ④ 離れすぎていない（価格とH4 EMAの距離 ＜ H4 ATR × 1.0）
   bool buyTrend = (r.slopeH4 > 0 && r.slopeH4Long > 0);
   bool buyAlign = (h1Now > h4Now);
   bool buyZone  = (r.pricePosH4 > 0 && r.pricePos < 0);
   bool buyDist  = (atrH4 > 0.0 && r.distH4 < atrH4 * 1.0);

   // --- v1.53 売り（戻り）4条件 ---
   bool sellTrend = (r.slopeH4 < 0 && r.slopeH4Long < 0);
   bool sellAlign = (h1Now < h4Now);
   bool sellZone  = (r.pricePosH4 < 0 && r.pricePos > 0);
   bool sellDist  = (atrH4 > 0.0 && r.distH4 < atrH4 * 1.0);

   if(buyTrend && buyAlign && buyZone && buyDist)
      r.dir = 1;
   else if(sellTrend && sellAlign && sellZone && sellDist)
      r.dir = -1;

   return true;
  }

//| ログ用：EMA_AlignCompute の結果を "key=value" にする              |
string EMA_AlignFeat(const EMA_ALIGN_Result &r)
  {
   return StringFormat("ema_dir=%d;slopeH4=%d;slopeH4Long=%d;slopeH1=%d;slopeD1=%d;pricePos=%d;pricePosH4=%d;emaH4=%.5f;emaH1=%.5f;price=%.5f;atrH4=%.5f;distH4=%.5f",
                       r.dir, r.slopeH4, r.slopeH4Long, r.slopeH1, r.slopeD1, r.pricePos, r.pricePosH4, r.emaH4, r.emaH1, r.price, r.atrH4, r.distH4);
  }
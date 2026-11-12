//+------------------------------------------------------------------+
//| EMAAlignmentEngine.mqh                                           |
//| H4/H1 200EMA + 圧縮の押し目 / 戻り判定                            |
//| ・圧縮エンジンとは独立。判定のみを行う                            |
//| ・iMAハンドルは symbol ごとにキャッシュする                       |
//+------------------------------------------------------------------+
#property copyright "EMA Alignment Engine"
#property version   "1.52"

struct EMA_ALIGN_Result
  {
   bool   ready;      // 計算できたか
   int    dir;        // 1=買い条件, -1=売り条件, 0=なし
   double emaH4;      // H4 200EMA (確定足 shift=1)
   double emaH1;      // H1 200EMA (確定足 shift=1)
   double emaD1;      // D1 200EMA (確定足 shift=1, UseD1=falseなら0)
   double price;      // H1 終値 (確定足 shift=1)
   int    slopeH4;    // 1=上, -1=下, 0=横ばい
   int    slopeH1;
   int    slopeD1;
   int    pricePos;   // 1=価格はH1 EMAより上, -1=下
  };

struct EMA_AlignHandle
  {
   string symbol;
   int    hH4;
   int    hH1;
   int    hD1;
  };

EMA_AlignHandle g_emaHandles[];
int             g_emaHandlePeriod = 200;

//+------------------------------------------------------------------+
//| ハンドル解放（OnDeinitから呼ぶ）                                  |
//+------------------------------------------------------------------+
void EMA_AlignRelease()
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
     {
      if(g_emaHandles[i].hH4 > 0) IndicatorRelease(g_emaHandles[i].hH4);
      if(g_emaHandles[i].hH1 > 0) IndicatorRelease(g_emaHandles[i].hH1);
      if(g_emaHandles[i].hD1 > 0) IndicatorRelease(g_emaHandles[i].hD1);
     }
   ArrayResize(g_emaHandles, 0);
  }

//+------------------------------------------------------------------+
//| 1本のEMA値を取る                                                  |
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
//| symbol のハンドルを取得（なければ作る、後から日足ON対応）          |
//+------------------------------------------------------------------+
int EMA_AlignHandleIndex(const string symbol, const int emaPeriod, const bool useD1, const bool useH4)
  {
   for(int i = 0; i < ArraySize(g_emaHandles); i++)
      if(g_emaHandles[i].symbol == symbol)
        {
         // 後からH4 / 日足をONにした場合、ハンドルだけ作り直す
         if(useH4 && g_emaHandles[i].hH4 <= 0)
            g_emaHandles[i].hH4 = iMA(symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
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
   g_emaHandlePeriod = emaPeriod;
   return idx;
  }

//+------------------------------------------------------------------+
//| 本体：H4/H1(+D1) 200EMA の向きと価格位置を判定                    |
//| ※ 確定足のみ使う。未確定足は見ない                                |
//| ※ v1.52：トレンドはH4、押し目はH1で分離。横ばいは0にする          |
//+------------------------------------------------------------------+
bool EMA_AlignCompute(const string symbol, const int emaPeriod, const int slopeBars, const bool useD1, const bool useH4, EMA_ALIGN_Result &r)
  {
   r.ready = false;
   r.dir = 0;
   r.emaH4 = 0.0; r.emaH1 = 0.0; r.emaD1 = 0.0; r.price = 0.0;
   r.slopeH4 = 0; r.slopeH1 = 0; r.slopeD1 = 0; r.pricePos = 0;
   int hi = EMA_AlignHandleIndex(symbol, emaPeriod, useD1, useH4);
   if(hi < 0) return false;

   int shiftNow = 1;
   int shiftOld = 1 + MathMax(1, slopeBars);

   double h4Now = 0.0, h4Old = 0.0, h1Now = 0.0, h1Old = 0.0, d1Now = 0.0, d1Old = 0.0;
   if(useH4)
     {
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftNow, h4Now)) return false;
      if(!EMA_GetValue(g_emaHandles[hi].hH4, shiftOld, h4Old)) return false;
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

   // --- 向き判定：誤差でブレないように「横ばい帯」を作る ---
   // EMAが価格の0.02%も動いていなければ横ばい扱い
   double epsH4 = h4Now * 0.0001;
   double epsH1 = h1Now * 0.0001;
   double epsD1 = d1Now * 0.0001;

   r.slopeH4 = useH4 ? ((h4Now - h4Old) > epsH4 ? 1 : ((h4Old - h4Now) > epsH4 ? -1 : 0)) : 0;
   r.slopeH1 = ((h1Now - h1Old) > epsH1 ? 1 : ((h1Old - h1Now) > epsH1 ? -1 : 0));
   r.slopeD1 = useD1 ? ((d1Now - d1Old) > epsD1 ? 1 : ((d1Old - d1Now) > epsD1 ? -1 : 0)) : 0;

   // --- 価格位置：H1だけじゃなくH4とも比べる ---
   r.pricePos = (close1 > h1Now ? 1 : (close1 < h1Now ? -1 : 0));
   int pricePosH4 = useH4 ? (close1 > h4Now ? 1 : (close1 < h4Now ? -1 : 0)) : 0;
   r.ready = true;

   // 日足フィルター：日足を使うなら、日足の向きがトレンドと揃っていること
   if(useD1)
     {
      int trendSlope = useH4 ? r.slopeH4 : r.slopeH1;
      if(trendSlope != 0 && r.slopeD1 != 0 && r.slopeD1 != trendSlope) return true;
     }

   // 買い（押し目）：H4が上向き + 価格はH4 EMAより上 + 価格はH1 EMAより下
   // ※ H1が少し下向きでもOK。押し目中はH1 EMAが下を向くのが普通だから
   if((!useH4 || r.slopeH4 > 0) && pricePosH4 > 0 && r.pricePos < 0)
      r.dir = 1;
   // 売り（戻り）：H4が下向き + 価格はH4 EMAより下 + 価格はH1 EMAより上
   else if((!useH4 || r.slopeH4 < 0) && pricePosH4 < 0 && r.pricePos > 0)
      r.dir = -1;
   // H4を使わない場合のフォールバック（今まで通り）
   else if(!useH4)
     {
      if(r.slopeH1 > 0 && r.pricePos < 0)
         r.dir = 1;
      else if(r.slopeH1 < 0 && r.pricePos > 0)
         r.dir = -1;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| ログ用：EMA_AlignCompute の結果を "key=value" にする              |
//+------------------------------------------------------------------+
string EMA_AlignFeat(const EMA_ALIGN_Result &r)
  {
   return StringFormat("ema_dir=%d;slopeH4=%d;slopeH1=%d;slopeD1=%d;pricePos=%d;emaH4=%.5f;emaH1=%.5f;price=%.5f",
                       r.dir, r.slopeH4, r.slopeH1, r.slopeD1, r.pricePos, r.emaH4, r.emaH1, r.price);
  }
//+------------------------------------------------------------------+
//|                                        RelatedPairEngine.mqh      |
//|  関連通貨エンジン(予兆スコア)                                     |
//|                                                                    |
//|  「関連する通貨ペアが急変・圧縮している時は、この通貨ペアも          |
//|   まもなく動きやすい」という考え方を、予兆スコア(%)にする。         |
//|                                                                    |
//|  1. 関連ペアの決め方: 同じ時間足の値動き(騰落率)の相関係数を計算し、  |
//|     |相関係数| が REL_MinCorr 以上のペアを「関連あり」とする。      |
//|     (符号は問わない。逆相関も関連として扱い、方向の目安に使う)     |
//|  2. 予兆スコア = 次の4要素の重みづけ平均(0〜100%)                  |
//|       自身の圧縮度 / 関連ペアの圧縮度 / 関連ペアの急変 / 指標・開場  |
//|                                                                    |
//|  【重要】これは確率ではなく、重みづけした「目安」。                  |
//|  実際の的中率とは一致しない。検証ログ(SignalLogger)に予兆スコアを  |
//|  記録し、スコア帯ごとの的中率を見て重みを調整していく前提の設計。   |
//+------------------------------------------------------------------+
#property strict

input group "=== 関連通貨エンジン(予兆スコア) ==="
input bool   REL_Enable    = true;  // 予兆スコアを計算する
input int    REL_CorrBars  = 100;   // 相関係数の計算に使う本数
input double REL_MinCorr   = 0.5;   // 「関連あり」とみなす|相関係数|の下限
input int    REL_RefreshMin = 30;   // 相関係数の再計算間隔(分)
input double REL_WSelf     = 0.35;  // 重み: 自身の圧縮度
input double REL_WRelComp  = 0.20;  // 重み: 関連ペアの圧縮度
input double REL_WRelSpike = 0.30;  // 重み: 関連ペアの急変
input double REL_WEvent    = 0.15;  // 重み: 指標発表・市場開場の近さ

string          g_relSyms[];
ENUM_TIMEFRAMES g_relTfs[];
int             g_relN = 0;
int             g_relTfCount = 0;
double          g_relCorr[];      // [tf][i][j] を1次元に展開した相関係数
datetime        g_relLast[];      // 時間足ごとの最終計算時刻
bool            g_relReady = false;

struct REL_Result
  {
   double pct;        // 予兆スコア(0〜100)
   double compSelf;   // 自身の圧縮度(0〜1)
   double compRel;    // 関連ペアの圧縮度(0〜1)
   double spikeRel;   // 関連ペアの急変度(0〜1)
   double event;      // 指標・開場の近さ(0〜1)
   int    dir;        // 方向の目安: 1=上 -1=下 0=不明
   int    nRelated;   // 関連ペアの数
   string topSpike;   // 急変中の関連ペア(相関が最も強いもの)
   string topComp;    // 強く圧縮中の関連ペア(相関が最も強いもの)
  };

//+------------------------------------------------------------------+
bool REL_Init(const string &symbols[], const int n, const ENUM_TIMEFRAMES &tfs[], const int tfCount)
  {
   g_relReady = false;
   if(n <= 1 || tfCount <= 0)
      return false;

   g_relN = n;
   g_relTfCount = tfCount;
   ArrayResize(g_relSyms, n);
   ArrayResize(g_relTfs, tfCount);
   for(int i = 0; i < n; i++)        g_relSyms[i] = symbols[i];
   for(int t = 0; t < tfCount; t++)  g_relTfs[t]  = tfs[t];

   ArrayResize(g_relCorr, tfCount * n * n);
   ArrayInitialize(g_relCorr, 0.0);
   ArrayResize(g_relLast, tfCount);
   for(int t = 0; t < tfCount; t++)  g_relLast[t] = 0;

   g_relReady = true;
   return true;
  }

//+------------------------------------------------------------------+
//| 2つの銘柄の相関係数。時刻が一致する足だけを使う(土日や取引時間の違いに対応) |
//+------------------------------------------------------------------+
double REL_PairCorr(const datetime &times[], const double &closes[], const int L,
                    const int &cnt[], const int i, const int j, const int bars)
  {
   int maxPts = bars + 1;
   double ca[], cb[];
   ArrayResize(ca, maxPts);
   ArrayResize(cb, maxPts);

   int a = 0, b = 0, m = 0;
   while(a < cnt[i] && b < cnt[j] && m < maxPts)
     {
      datetime ta = times[i * L + a];
      datetime tb = times[j * L + b];
      if(ta == tb)
        {
         ca[m] = closes[i * L + a];
         cb[m] = closes[j * L + b];
         m++; a++; b++;
        }
      else if(ta > tb)
         a++;
      else
         b++;
     }
   if(m < 31)
      return 0.0;

   int nr = m - 1;
   double ra[], rb[];
   ArrayResize(ra, nr);
   ArrayResize(rb, nr);
   for(int k = 0; k < nr; k++)
     {
      ra[k] = (ca[k + 1] != 0.0) ? (ca[k] - ca[k + 1]) / ca[k + 1] : 0.0;
      rb[k] = (cb[k + 1] != 0.0) ? (cb[k] - cb[k + 1]) / cb[k + 1] : 0.0;
     }

   double ma = 0.0, mb = 0.0;
   for(int k = 0; k < nr; k++) { ma += ra[k]; mb += rb[k]; }
   ma /= nr;
   mb /= nr;

   double cov = 0.0, va = 0.0, vb = 0.0;
   for(int k = 0; k < nr; k++)
     {
      double da = ra[k] - ma;
      double db = rb[k] - mb;
      cov += da * db;
      va  += da * da;
      vb  += db * db;
     }
   if(va <= 0.0 || vb <= 0.0)
      return 0.0;
   return cov / MathSqrt(va * vb);
  }

//+------------------------------------------------------------------+
//| 1つの時間足について、全銘柄ペアの相関係数を計算してキャッシュする  |
//+------------------------------------------------------------------+
void REL_ComputeTF(const int t)
  {
   int n = g_relN;
   int bars = REL_CorrBars;
   int L = bars + 20;

   datetime times[];
   double   closes[];
   int      cnt[];
   ArrayResize(times,  n * L);
   ArrayResize(closes, n * L);
   ArrayResize(cnt, n);

   for(int s = 0; s < n; s++)
     {
      datetime tt[];
      double   cc[];
      ArraySetAsSeries(tt, true);
      ArraySetAsSeries(cc, true);
      int g1 = CopyTime(g_relSyms[s], g_relTfs[t], 1, L, tt);
      int g2 = CopyClose(g_relSyms[s], g_relTfs[t], 1, L, cc);
      int got = MathMin(g1, g2);
      if(got <= 0) { cnt[s] = 0; continue; }
      cnt[s] = got;
      for(int k = 0; k < got; k++)
        {
         times[s * L + k]  = tt[k];
         closes[s * L + k] = cc[k];
        }
     }

   int base = t * n * n;
   for(int i = 0; i < n; i++)
     {
      g_relCorr[base + i * n + i] = 1.0;
      for(int j = i + 1; j < n; j++)
        {
         double r = REL_PairCorr(times, closes, L, cnt, i, j, bars);
         g_relCorr[base + i * n + j] = r;
         g_relCorr[base + j * n + i] = r;
        }
     }
  }

//+------------------------------------------------------------------+
//| 毎周期呼ぶ。相関係数の再計算が必要な時間足を、1周期に1つだけ処理する |
//+------------------------------------------------------------------+
void REL_Update()
  {
   if(!REL_Enable || !g_relReady)
      return;
   datetime now = TimeCurrent();
   for(int t = 0; t < g_relTfCount; t++)
     {
      if(now - g_relLast[t] >= REL_RefreshMin * 60)
        {
         REL_ComputeTF(t);
         g_relLast[t] = now;
         return;
        }
     }
  }

double REL_GetCorr(const int tfIdx, const int i, const int j)
  {
   if(!g_relReady) return 0.0;
   return g_relCorr[tfIdx * g_relN * g_relN + i * g_relN + j];
  }

//+------------------------------------------------------------------+
//| 予兆スコアを計算する                                               |
//|  symIdx/tfIdx : 対象の銘柄・時間足(Initに渡した並びでの番号)      |
//|  score[]      : 各銘柄の圧縮Score。添字は tfIdx*n + 銘柄番号       |
//|  act[] / up[] : 各銘柄が急変中か / 上昇方向か(添字は同じ)          |
//|  selfScore    : 対象自身の圧縮Score(0〜8)                         |
//|  eventScore   : 指標・開場の近さ(0〜1。EventTimeEngineから)        |
//+------------------------------------------------------------------+
void REL_Compute(const int symIdx, const int tfIdx,
                 const int &score[], const bool &act[], const bool &up[],
                 const int selfScore, const double eventScore, REL_Result &res)
  {
   res.pct = 0.0;
   res.compSelf = 0.0;
   res.compRel = 0.0;
   res.spikeRel = 0.0;
   res.event = eventScore;
   res.dir = 0;
   res.nRelated = 0;
   res.topSpike = "";
   res.topComp = "";

   if(!REL_Enable || !g_relReady)
      return;

   int n = g_relN;
   int off = tfIdx * n;
   if(ArraySize(score) < off + n || ArraySize(act) < off + n || ArraySize(up) < off + n)
      return;

   double wSum = 0.0, compW = 0.0, spikeSum = 0.0, dirSum = 0.0;
   double bestSpikeW = 0.0, bestCompW = 0.0;

   for(int j = 0; j < n; j++)
     {
      if(j == symIdx) continue;
      double r = REL_GetCorr(tfIdx, symIdx, j);
      double w = MathAbs(r);
      if(w < REL_MinCorr) continue;

      res.nRelated++;
      wSum  += w;
      compW += w * (double)score[off + j] / 8.0;

      // 強く圧縮中(Score5以上)の関連ペアのうち、相関が最も強いもの
      if(score[off + j] >= 5 && w > bestCompW)
        {
         bestCompW = w;
         res.topComp = StringFormat("%s(r=%+.2f)", g_relSyms[j], r);
        }

      // 急変中の関連ペア
      if(act[off + j])
        {
         spikeSum += w;
         double sgn = ((r >= 0.0) ? 1.0 : -1.0) * (up[off + j] ? 1.0 : -1.0);
         dirSum += w * sgn;
         if(w > bestSpikeW)
           {
            bestSpikeW = w;
            res.topSpike = StringFormat("%s(r=%+.2f)", g_relSyms[j], r);
           }
        }
     }

   res.compSelf = (double)selfScore / 8.0;
   res.compRel  = (wSum > 0.0) ? compW / wSum : 0.0;
   res.spikeRel = MathMin(1.0, spikeSum);   // 相関1.0の関連ペア1本が急変中なら1.0

   double wTot = REL_WSelf + REL_WRelComp + REL_WRelSpike + REL_WEvent;
   if(wTot <= 0.0) wTot = 1.0;
   res.pct = 100.0 * (REL_WSelf * res.compSelf + REL_WRelComp * res.compRel
                      + REL_WRelSpike * res.spikeRel + REL_WEvent * res.event) / wTot;

   if(dirSum > 0.3)       res.dir = 1;
   else if(dirSum < -0.3) res.dir = -1;
  }
//+------------------------------------------------------------------+

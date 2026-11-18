//|                                               TTMSqueezeEngine.mqh |
//|  TTM Squeeze エンジン (スクイーズ + モメンタム)                      |
//|                                                                    |
//|  ・BB(20, 2.0) が KC(20, 1.5) の内側に入ったらスクイーズ            |
//|  ・モメンタム = 線形回帰の傾き (終値 - HL2/3平均)                   |
//|  ・圧縮エンジン本体は触らない。別エンジン。                          |
//|  ・確定足だけで、毎回過去から計算する(ステートレス)。                |
#property strict

input group "=== TTM Squeeze ==="
input bool   TTM_Enable      = true;   // TTM Squeeze を計算する
input int    TTM_BB_Period   = 20;     // ボリンジャー期間
input double TTM_BB_Dev      = 2.0;    // ボリンジャー偏差
input int    TTM_KC_Period   = 20;     // ケルトナー期間
input double TTM_KC_Mult     = 1.5;    // ケルトナー ATR倍率
input int    TTM_Mom_Period  = 12;     // モメンタムの線形回帰に使う本数
input int    TTM_SqzBars     = 3;      // スクイーズ解除を「直近」とみなす本数
input bool   TTM_ShowInList  = true;   // 一覧に TTM の表示を付ける

struct TTM_Result
  {
   bool   ready;
   bool   squeeze;     // 今スクイーズ中か
   int    squeezeBars; // スクイーズが何本続いてるか
   bool   released;    // 直近でスクイーズを解除したか
   int    releaseAgo;  // 解除から何本前か (-1=なし)
   double momentum;    // モメンタム (線形回帰の傾き)
   int    momDir;      // +1=モメンタム上 -1=下 0=ほぼ0
   double momUp;       // モメンタムがプラスに転じて何本か
   double momDown;     // モメンタムがマイナスに転じて何本か
  };

//| 計算 (最後の確定足の時点の状態を求める)                            |
bool TTM_Compute(const string symbol, const ENUM_TIMEFRAMES tf, TTM_Result &r)
  {
   r.ready = false;
   r.squeeze = false;
   r.squeezeBars = 0;
   r.released = false;
   r.releaseAgo = -1;
   r.momentum = 0.0;
   r.momDir = 0;
   r.momUp = 0;
   r.momDown = 0;

   if(!TTM_Enable)
      return false;

   int need = MathMax(TTM_BB_Period, TTM_KC_Period) + TTM_Mom_Period + 30;
   double h[], l[], c[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   int g1 = CopyHigh(symbol, tf, 1, need, h);
   int g2 = CopyLow(symbol, tf, 1, need, l);
   int g3 = CopyClose(symbol, tf, 1, need, c);
   int got = MathMin(g1, MathMin(g2, g3));
   if(got < need)
      return false;

   //--- 各足の BB / KC / モメンタムを求める ---
   int M = TTM_SqzBars + 20; // 0〜M の足について求める
   bool   sqz[];
   double mom[];
   ArrayResize(sqz, M + 1);
   ArrayResize(mom, M + 1);

   for(int i = 0; i <= M; i++)
     {
      //--- BB (SMA + 偏差×標準偏差) ---
      int bp = MathMax(2, TTM_BB_Period);
      double sum = 0.0;
      for(int k = 0; k < bp; k++) sum += c[i + k];
      double sma = sum / bp;
      double var = 0.0;
      for(int k = 0; k < bp; k++) var += (c[i + k] - sma) * (c[i + k] - sma);
      double sd = MathSqrt(var / bp);
      double bbUp = sma + TTM_BB_Dev * sd;
      double bbDn = sma - TTM_BB_Dev * sd;

      //--- KC (EMA + ATR×倍率) ---
      int kp = MathMax(2, TTM_KC_Period);
      // EMA (簡易：SMAで代用。スクイーズ判定には十分)
      double esum = 0.0;
      for(int k = 0; k < kp; k++) esum += c[i + k];
      double ema = esum / kp;
      // ATR (簡易：TRの単純平均)
      double tsum = 0.0;
      for(int k = 0; k < kp; k++)
        {
         double tr = h[i + k] - l[i + k];
         double tr2 = MathAbs(h[i + k] - c[i + k + 1]);
         double tr3 = MathAbs(l[i + k] - c[i + k + 1]);
         tsum += MathMax(tr, MathMax(tr2, tr3));
        }
      double atr = tsum / kp;
      double kcUp = ema + TTM_KC_Mult * atr;
      double kcDn = ema - TTM_KC_Mult * atr;

      sqz[i] = (bbUp < kcUp && bbDn > kcDn);

      //--- モメンタム (線形回帰の傾き) ---
      // 値 = 終値 - (高値+安値+終値)/3 の平均
      int mp = MathMax(3, TTM_Mom_Period);
      double xs = 0.0, ys = 0.0, xys = 0.0, x2s = 0.0;
      for(int k = 0; k < mp; k++)
        {
         double hl2 = (h[i + k] + l[i + k] + c[i + k]) / 3.0;
         double v = c[i + k] - hl2;
         double x = (double)k;
         xs += x; ys += v; xys += x * v; x2s += x * x;
        }
      double denom = mp * x2s - xs * xs;
      double slope = (denom != 0.0) ? (mp * xys - xs * ys) / denom : 0.0;
      // x は古いほど大きいので、符号を反転して「新しい方向の傾き」にする
      mom[i] = -slope;
     }

   r.squeeze = sqz[0];
   r.momentum = mom[0];

   // スクイーズが何本続いてるか
   int sb = 0;
   for(int i = 0; i <= M; i++)
     {
      if(sqz[i]) sb++;
      else break;
     }
   r.squeezeBars = sb;

   // 直近でスクイーズを解除したか
   for(int i = 0; i < TTM_SqzBars; i++)
     {
      if(!sqz[i] && sqz[i + 1])
        {
         r.released = true;
         r.releaseAgo = i;
         break;
        }
     }

   // モメンタムの向き
   if(r.momentum > 0.0) r.momDir = 1;
   else if(r.momentum < 0.0) r.momDir = -1;
   else r.momDir = 0;

   // モメンタムがプラス / マイナスに転じて何本か
   int up = 0, dn = 0;
   for(int i = 0; i <= M; i++)
     {
      if(mom[i] > 0.0) { if(dn == 0) up++; else break; }
      else if(mom[i] < 0.0) { if(up == 0) dn++; else break; }
      else break;
     }
   r.momUp = up;
   r.momDown = dn;

   r.ready = true;
   return true;
  }

//| 表示・判定・ログ用                                                 |
//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string TTM_Text(const TTM_Result &r)
  {
   if(!r.ready)
      return "";
   string t = "";
   if(r.squeeze)
      t += StringFormat("SQZ%d本", r.squeezeBars);
   else if(r.released)
     {
      t += "SQZ解除";
      if(r.releaseAgo > 0) t += StringFormat("(%d本前)", r.releaseAgo);
     }
   if(r.momDir != 0)
     {
      if(StringLen(t) > 0) t += " ";
      t += (r.momDir > 0) ? "Mom↑" : "Mom↓";
     }
   if(StringLen(t) == 0)
      return "";
   return "  [TTM " + t + "]";
  }

//--- 検証ログ用の特徴量 (ASCIIのみ。カンマは使わない)
string TTM_Feat(const TTM_Result &r)
  {
   if(!r.ready)
      return "ttm_ready=0";
   return StringFormat("ttm_sqz=%d;ttm_bars=%d;ttm_rel=%d;ttm_ago=%d;ttm_mom=%.5f;ttm_dir=%d",
                       r.squeeze ? 1 : 0, r.squeezeBars,
                       r.released ? 1 : 0, r.releaseAgo,
                       r.momentum, r.momDir);
  }
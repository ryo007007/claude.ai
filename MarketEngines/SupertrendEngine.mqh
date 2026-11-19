//+------------------------------------------------------------------+
//|                                             SupertrendEngine.mqh |
//|  Supertrend エンジン (トレンドフィルター)                          |
//|                                                                    |
//|  ・ATRバンド (HL2 ± ATR×倍率) を使う                               |
//|  ・価格がバンドを抜けたらトレンド反転                               |
//|  ・圧縮エンジン本体は触らない。別エンジン。                          |
//|  ・確定足だけで、毎回過去から計算する(ステートレス)。                |
//+------------------------------------------------------------------+
#property strict

input group "=== Supertrend ==="
input bool   ST_Enable      = true;   // Supertrendを計算する
input int    ST_ATR_Period  = 10;     // ATR期間
input double ST_ATR_Mult    = 3.0;    // ATR倍率
input int    ST_Lookback    = 100;    // 探す過去の本数 (トレンド継続本数の計算用)
input int    ST_RecentBars  = 3;      // 反転を「直近」とみなす本数
input bool   ST_ShowInList  = true;   // 一覧に Supertrendの表示を付ける

struct ST_Result
  {
   bool   ready;
   int    dir;         // +1=上昇トレンド -1=下降トレンド 0=なし
   double line;        // Supertrendラインの値
   int    trendBars;   // 今のトレンドが何本続いてるか
   bool   flipped;     // 直近で反転したか
   int    flipAgo;     // 反転から何本前か (-1=なし)
   double atr;         // ATR
   double upper;       // 上バンド
   double lower;       // 下バンド
  };

//+------------------------------------------------------------------+
//| 計算 (最後の確定足の時点の状態を求める)                            |
//+------------------------------------------------------------------+
bool ST_Compute(const string symbol, const ENUM_TIMEFRAMES tf, ST_Result &r)
  {
   r.ready = false;
   r.dir = 0;
   r.line = 0.0;
   r.trendBars = 0;
   r.flipped = false;
   r.flipAgo = -1;
   r.atr = 0.0;
   r.upper = 0.0;
   r.lower = 0.0;

   if(!ST_Enable)
      return false;

   int need = MathMax(30, ST_Lookback) + ST_ATR_Period + 20;
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

   int ap = MathMax(2, ST_ATR_Period);
   double mult = ST_ATR_Mult;

   //--- 古い足から新しい足へ向かって Supertrend を計算 ---
   // 添字が大きい = 古い足、0 = 最新の確定足
   // 計算は古い方からやるので、i = got-1 から 0 へ
   double prevUpper = 0.0, prevLower = 0.0;
   double prevLine = 0.0;
   int prevDir = 1; // 最初は上昇と仮定
   bool first = true;

   // 直近のトレンド履歴を残す (反転検出用)
   int dirHist[];
   ArrayResize(dirHist, ST_RecentBars + 20);
   ArrayInitialize(dirHist, 0);

   for(int i = got - 1; i >= 0; i--)
     {
      //--- ATR (簡易：TRの単純平均) ---
      double atrSum = 0.0;
      int atrCount = 0;
      for(int k = 0; k < ap; k++)
        {
         int idx = i + k;
         if(idx + 1 >= got) break;
         double tr = h[idx] - l[idx];
         tr = MathMax(tr, MathMax(MathAbs(h[idx] - c[idx + 1]), MathAbs(l[idx] - c[idx + 1])));
         atrSum += tr;
         atrCount++;
        }
      if(atrCount == 0) continue;
      double atr = atrSum / atrCount;

      double hl2 = (h[i] + l[i]) / 2.0;
      double basicUpper = hl2 + mult * atr;
      double basicLower = hl2 - mult * atr;

      double finalUpper = basicUpper;
      double finalLower = basicLower;

      if(!first)
        {
         // 前のバンドを引き継ぐ (バンドは価格に近づく方向にしか動かない)
         if(prevDir > 0)
           {
            // 上昇中は、下バンドは上がる方向にしか動かない
            if(basicLower < prevLower) finalLower = prevLower;
           }
         else
           {
            // 下降中は、上バンドは下がる方向にしか動かない
            if(basicUpper > prevUpper) finalUpper = prevUpper;
           }
        }

      int dir = prevDir;
      double line = prevLine;
      if(first)
        {
         // 最初は終値で判定
         if(c[i] > finalUpper) { dir = 1; line = finalLower; }
         else if(c[i] < finalLower) { dir = -1; line = finalUpper; }
         else { dir = 1; line = finalLower; }
        }
      else
        {
         if(prevDir > 0)
           {
            // 上昇中：終値が下バンドを割ったら下降へ
            if(c[i] < finalLower) { dir = -1; line = finalUpper; }
            else { dir = 1; line = finalLower; }
           }
         else
           {
            // 下降中：終値が上バンドを超えたら上昇へ
            if(c[i] > finalUpper) { dir = 1; line = finalLower; }
            else { dir = -1; line = finalUpper; }
           }
        }

      prevUpper = finalUpper;
      prevLower = finalLower;
      prevLine = line;
      prevDir = dir;
      first = false;

      // 最新の足の結果を保存
      if(i == 0)
        {
         r.dir = dir;
         r.line = line;
         r.atr = atr;
         r.upper = finalUpper;
         r.lower = finalLower;
        }

      // 直近の方向履歴 (i が小さい = 新しい)
      if(i < ArraySize(dirHist))
         dirHist[i] = dir;
     }

   // トレンドが何本続いてるか
   int tb = 0;
   for(int i = 0; i < ST_Lookback && i < ArraySize(dirHist); i++)
     {
      if(dirHist[i] == r.dir) tb++;
      else break;
     }
   r.trendBars = tb;

   // 直近で反転したか
   for(int i = 0; i < ST_RecentBars; i++)
     {
      if(dirHist[i] != dirHist[i + 1] && dirHist[i + 1] != 0)
        {
         r.flipped = true;
         r.flipAgo = i;
         break;
        }
     }

   r.ready = true;
   return true;
  }

//+------------------------------------------------------------------+
//| 表示・判定・ログ用                                                 |
//+------------------------------------------------------------------+
//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string ST_Text(const ST_Result &r)
  {
   if(!r.ready)
      return "";
   if(r.dir == 0)
      return "";
   string t = "";
   if(r.dir > 0) t = "ST↑";
   else          t = "ST↓";
   if(r.flipped) t += "(反転)";
   return "  [" + t + "]";
  }

//--- 検証ログ用の特徴量 (ASCIIのみ。カンマは使わない)
string ST_Feat(const ST_Result &r)
  {
   if(!r.ready)
      return "st_ready=0";
   return StringFormat("st_dir=%d;st_bars=%d;st_flip=%d;st_ago=%d;st_line=%.5f;st_atr=%.5f",
                       r.dir, r.trendBars, r.flipped ? 1 : 0, r.flipAgo,
                       r.line, r.atr);
  }
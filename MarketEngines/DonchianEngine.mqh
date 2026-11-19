// DonchianEngine.mqh
// Donchian チャネル エンジン (ブレイク方向フィルター)
// 過去N本の最高値・最安値をバンドにする
// 圧縮エンジン本体は触らない。別エンジン。
// 確定足だけで、毎回過去から計算する(ステートレス)。
#property strict

input group "=== Donchian ==="
input bool   DON_Enable      = true;   // Donchianを計算する
input int    DON_Period      = 20;     // Donchian期間
input int    DON_Lookback    = 100;    // 探す過去の本数
input int    DON_RecentBars  = 3;      // ブレイクを「直近」とみなす本数
input bool   DON_ShowInList  = true;   // 一覧に Donchianの表示を付ける

struct DON_Result
  {
   bool   ready;
   int    dir;         // +1=上ブレイク中 -1=下ブレイク中 0=レンジ内
   double upper;       // 上バンド (過去N本の最高値)
   double lower;       // 下バンド (過去N本の最安値)
   double mid;         // 中間値
   int    pos;         // +1=上半分 -1=下半分 0=中間付近
   bool   brokeUp;     // 直近で上ブレイクしたか
   bool   brokeDown;   // 直近で下ブレイクしたか
   int    breakAgo;    // ブレイクから何本前か (-1=なし)
   double width;       // バンド幅
   double widthPct;    // バンド幅を価格で割ったもの (%)
  };

// 計算 (最後の確定足の時点の状態を求める)
bool DON_Compute(const string symbol, const ENUM_TIMEFRAMES tf, DON_Result &r)
  {
   r.ready = false;
   r.dir = 0;
   r.upper = 0.0;
   r.lower = 0.0;
   r.mid = 0.0;
   r.pos = 0;
   r.brokeUp = false;
   r.brokeDown = false;
   r.breakAgo = -1;
   r.width = 0.0;
   r.widthPct = 0.0;

   if(!DON_Enable)
      return false;

   int need = MathMax(30, DON_Lookback) + DON_Period + 20;
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

   int dp = MathMax(2, DON_Period);

   // 各足の Donchian バンドを求める
   int M = DON_RecentBars + 20;
   double upArr[];
   double dnArr[];
   ArrayResize(upArr, M + 1);
   ArrayResize(dnArr, M + 1);

   for(int i = 0; i <= M; i++)
     {
      double hi = h[i];
      double lo = l[i];
      for(int k = 1; k < dp; k++)
        {
         if(h[i + k] > hi) hi = h[i + k];
         if(l[i + k] < lo) lo = l[i + k];
        }
      upArr[i] = hi;
      dnArr[i] = lo;
     }

   r.upper = upArr[0];
   r.lower = dnArr[0];
   r.mid = (r.upper + r.lower) / 2.0;
   r.width = r.upper - r.lower;
   if(c[0] > 0.0)
      r.widthPct = r.width / c[0] * 100.0;

   // 価格の位置
   if(c[0] > r.mid)
      r.pos = 1;
   else if(c[0] < r.mid)
      r.pos = -1;
   else
      r.pos = 0;

   // ブレイク判定 (終値がバンドを超えたか)
   // 上ブレイク：終値が1本前の上バンドより上
   // 下ブレイク：終値が1本前の下バンドより下
   bool upBreak = false;
   bool dnBreak = false;
   int upAgo = -1;
   int dnAgo = -1;

   for(int i = 0; i < DON_RecentBars; i++)
     {
      if(c[i] > upArr[i + 1])
        {
         upBreak = true;
         if(upAgo < 0) upAgo = i;
        }
      if(c[i] < dnArr[i + 1])
        {
         dnBreak = true;
         if(dnAgo < 0) dnAgo = i;
        }
     }

   r.brokeUp = upBreak;
   r.brokeDown = dnBreak;

   // 方向 (新しい方のブレイクを優先)
   if(upBreak && dnBreak)
     {
      if(upAgo <= dnAgo)
        {
         r.dir = 1;
         r.breakAgo = upAgo;
        }
      else
        {
         r.dir = -1;
         r.breakAgo = dnAgo;
        }
     }
   else if(upBreak)
     {
      r.dir = 1;
      r.breakAgo = upAgo;
     }
   else if(dnBreak)
     {
      r.dir = -1;
      r.breakAgo = dnAgo;
     }
   else
     {
      r.dir = 0;
      r.breakAgo = -1;
     }

   r.ready = true;
   return true;
  }

// 一覧に付ける短い表示。表示すべき内容がなければ ""
string DON_Text(const DON_Result &r)
  {
   if(!r.ready)
      return "";
   if(r.dir == 0)
      return "";
   string t = "";
   if(r.dir > 0) t = "DON↑";
   else          t = "DON↓";
   if(r.breakAgo == 0) t += "(ブレイク)";
   return "  [" + t + "]";
  }

// 検証ログ用の特徴量 (ASCIIのみ。カンマは使わない)
string DON_Feat(const DON_Result &r)
  {
   if(!r.ready)
      return "don_ready=0";
   return StringFormat("don_dir=%d;don_pos=%d;don_up=%d;don_dn=%d;don_ago=%d;don_w=%.5f;don_wp=%.3f",
                       r.dir, r.pos,
                       r.brokeUp ? 1 : 0, r.brokeDown ? 1 : 0, r.breakAgo,
                       r.width, r.widthPct);
  }
//|                                            RSIDivergenceEngine.mqh |
//|  RSI ダイバージェンス エンジン                                      |
//|                                                                    |
//|  ・価格の高値・安値と、RSIの高値・安値を比較する                     |
//|  ・通常ダイバージェンスのみ (ヒドゥンはなし。まずはこちらで検証)    |
//|  ・圧縮エンジン本体は触らない。別エンジン。                          |
//|  ・確定足だけで、毎回過去から計算する(ステートレス)。                |
#property strict

input group "=== RSI ダイバージェンス ==="
input bool   RSI_Enable      = true;   // RSIダイバージェンスを計算する
input int    RSI_Period      = 14;     // RSI期間
input int    RSI_Lookback    = 60;     // 探す過去の本数
input int    RSI_SwingBars   = 3;      // スイング高値/安値の判定に使う左右の本数
input int    RSI_RecentBars  = 3;      // ダイバージェンスを「直近」とみなす本数
input double RSI_MinMove     = 0.5;    // 価格の2つ目の高値・安値が、1つ目より最低これだけ動いてないと無視 (ATR倍)
input bool   RSI_ShowInList  = true;   // 一覧に RSIダイバージェンスの表示を付ける

struct RSI_Result
  {
   bool   ready;
   double rsiNow;      // 最新の確定足の RSI
   int    divDir;      // +1=買いダイバ (価格安値切り下げ + RSI安値切り上げ)
                        // -1=売りダイバ (価格高値切り上げ + RSI高値切り下げ)
                        //  0=なし
   int    divAgo;      // ダイバージェンスが何本前か (-1=なし)
   bool   recent;      // RSI_RecentBars以内にダイバージェンスがある
   double price1;      // 1つ目の価格の高値・安値
   double price2;      // 2つ目の価格の高値・安値
   double rsi1;        // 1つ目の RSI
   double rsi2;        // 2つ目の RSI
   int    strength;    // 強さ 0〜100 (RSIの逆行幅が大きいほど強い)
  };

//| 計算 (最後の確定足の時点の状態を求める)                            |
bool RSI_Compute(const string symbol, const ENUM_TIMEFRAMES tf, RSI_Result &r)
  {
   r.ready = false;
   r.rsiNow = 50.0;
   r.divDir = 0;
   r.divAgo = -1;
   r.recent = false;
   r.price1 = 0.0; r.price2 = 0.0;
   r.rsi1 = 0.0;   r.rsi2 = 0.0;
   r.strength = 0;

   if(!RSI_Enable)
      return false;

   int need = MathMax(30, RSI_Lookback) + RSI_Period + 20;
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

   //--- ATR (価格の動きの基準) ---
   double atr = 0.0;
   for(int i = 0; i < 14; i++)
     {
      double tr = h[i] - l[i];
      tr = MathMax(tr, MathMax(MathAbs(h[i] - c[i + 1]), MathAbs(l[i] - c[i + 1])));
      atr += tr;
     }
   atr /= 14.0;
   if(atr <= 0.0)
      return false;

   //--- RSI (Wilder方式) ---
   int rp = MathMax(2, RSI_Period);
   double rsi[];
   ArrayResize(rsi, got);
   // 最初の平均
   double gain = 0.0, loss = 0.0;
   for(int i = got - 1; i > got - 1 - rp; i--)
     {
      double d = c[i - 1] - c[i]; // i-1 が新しい足
      if(d > 0) gain += d;
      else loss += -d;
     }
   gain /= rp; loss /= rp;
   // 古い足から新しい足へ向かって計算 (添字が大きい→小さい)
   // rsi[got-1-rp] から始める
   for(int i = got - 1 - rp; i >= 0; i--)
     {
      double d = c[i] - c[i + 1];
      if(d > 0)
        {
         gain = (gain * (rp - 1) + d) / rp;
         loss = (loss * (rp - 1)) / rp;
        }
      else
        {
         gain = (gain * (rp - 1)) / rp;
         loss = (loss * (rp - 1) + (-d)) / rp;
        }
      double rs = (loss == 0.0) ? 100.0 : gain / loss;
      rsi[i] = 100.0 - (100.0 / (1.0 + rs));
     }
   // 計算できてない古い部分は 50 で埋める
   for(int i = got - 1; i > got - 1 - rp; i--) rsi[i] = 50.0;

   r.rsiNow = rsi[0];

   //--- スイング高値・安値 (価格) と、その時点の RSI を探す ---
   int sb = MathMax(1, RSI_SwingBars);
   // 直近の2つの高値 / 2つの安値
   double hiP1 = 0, hiP2 = 0, hiR1 = 0, hiR2 = 0;
   int hiI1 = -1, hiI2 = -1;
   double loP1 = 0, loP2 = 0, loR1 = 0, loR2 = 0;
   int loI1 = -1, loI2 = -1;

   int lb = MathMin(got - sb - 1, RSI_Lookback);
   for(int i = sb; i <= lb; i++)
     {
      // 高値スイングか
      bool isH = true;
      for(int j = 1; j <= sb; j++)
        {
         if(h[i] <= h[i - j] || h[i] < h[i + j]) { isH = false; break; }
        }
      if(isH)
        {
         hiP2 = hiP1; hiR2 = hiR1; hiI2 = hiI1;
         hiP1 = h[i]; hiR1 = rsi[i]; hiI1 = i;
        }
      // 安値スイングか
      bool isL = true;
      for(int j = 1; j <= sb; j++)
        {
         if(l[i] >= l[i - j] || l[i] > l[i + j]) { isL = false; break; }
        }
      if(isL)
        {
         loP2 = loP1; loR2 = loR1; loI2 = loI1;
         loP1 = l[i]; loR1 = rsi[i]; loI1 = i;
        }
     }

   //--- 売りダイバージェンス：価格高値切り上げ + RSI高値切り下げ ---
   if(hiI1 >= 0 && hiI2 >= 0)
     {
      double priceMove = hiP1 - hiP2; // 新しい高値 - 古い高値
      double rsiMove = hiR1 - hiR2;   // 新しいRSI - 古いRSI
      if(priceMove > RSI_MinMove * atr && rsiMove < 0.0)
        {
         r.divDir = -1;
         r.divAgo = hiI1;
         r.price1 = hiP2; r.price2 = hiP1;
         r.rsi1 = hiR2;   r.rsi2 = hiR1;
         r.strength = (int)MathMin(100.0, MathAbs(rsiMove) * 5.0);
        }
     }

   //--- 買いダイバージェンス：価格安値切り下げ + RSI安値切り上げ ---
   // 売りと買いが両方ある場合は、新しい方を優先する
   if(loI1 >= 0 && loI2 >= 0)
     {
      double priceMove = loP2 - loP1; // 古い安値 - 新しい安値 (プラスなら切り下げ)
      double rsiMove = loR1 - loR2;  // 新しいRSI - 古いRSI
      if(priceMove > RSI_MinMove * atr && rsiMove > 0.0)
        {
         if(r.divDir == 0 || loI1 < r.divAgo)
           {
            r.divDir = 1;
            r.divAgo = loI1;
            r.price1 = loP2; r.price2 = loP1;
            r.rsi1 = loR2;   r.rsi2 = loR1;
            r.strength = (int)MathMin(100.0, MathAbs(rsiMove) * 5.0);
           }
        }
     }

   if(r.divDir != 0 && r.divAgo >= 0 && r.divAgo < RSI_RecentBars)
      r.recent = true;

   r.ready = true;
   return true;
  }

//| 表示・判定・ログ用                                                 |
//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string RSI_Text(const RSI_Result &r)
  {
   if(!r.ready)
      return "";
   if(r.divDir == 0)
      return "";
   string t = "";
   if(r.divDir > 0) t = "RSI買Div";
   else             t = "RSI売Div";
   if(r.divAgo > 0) t += StringFormat("(%d本前)", r.divAgo);
   if(r.recent) t += " 直近";
   return "  [" + t + "]";
  }

//--- 検証ログ用の特徴量 (ASCIIのみ。カンマは使わない)
string RSI_Feat(const RSI_Result &r)
  {
   if(!r.ready)
      return "rsi_ready=0";
   return StringFormat("rsi_now=%.1f;rsi_div=%d;rsi_ago=%d;rsi_recent=%d;rsi_str=%d;rsi_p1=%.5f;rsi_p2=%.5f;rsi_r1=%.1f;rsi_r2=%.1f",
                       r.rsiNow, r.divDir, r.divAgo, r.recent ? 1 : 0, r.strength,
                       r.price1, r.price2, r.rsi1, r.rsi2);
  }
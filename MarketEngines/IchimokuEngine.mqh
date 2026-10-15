//+------------------------------------------------------------------+
//|                                            IchimokuEngine.mqh     |
//|  一目均衡表エンジン(圧縮・解除の補助判定)                          |
//|                                                                    |
//|  CCompressionは「値幅が縮んでいるか」「解除が始まったか」を測るが、  |
//|  解除の【方向】は出せない。一目均衡表は、次の2点でそれを補う。      |
//|                                                                    |
//|  [圧縮の裏づけ]                                                   |
//|   ・雲が薄い(厚みが過去の分布の下位)                              |
//|   ・基準線が横ばい                                                 |
//|   ・価格が雲の中にある(方向感がない)                              |
//|  [解除の方向]                                                     |
//|   ・雲抜け(価格が雲の上/下へ出る)                                  |
//|   ・転換線と基準線のクロス(好転/逆転)                              |
//|   ・三役好転/逆転(転換線>基準線、雲の上、遅行スパン>26本前の価格)   |
//|   ・雲のねじれ(先行スパンA・Bの上下が入れ替わる)                   |
//|                                                                    |
//|  【位置づけ】                                                     |
//|  圧縮の判定(CCompressionのScore)は変えない。一目均衡表は補助情報。   |
//|  雲の厚みはATR/BB幅と相関が高いので、独立した情報とは限らない。      |
//|  解除の方向に効果があるかは、検証ログ(TRANSITION+ICHI)で確かめる。   |
//|                                                                    |
//|  確定足だけで、毎回過去から計算する(ステートレス)。                 |
//+------------------------------------------------------------------+
#property strict

input group "=== 一目均衡表 ==="
input bool   ICH_Enable       = true;   // 一目均衡表を計算する
input int    ICH_Tenkan       = 9;      // 転換線の期間
input int    ICH_Kijun        = 26;     // 基準線の期間
input int    ICH_SenkouB      = 52;     // 先行スパンBの期間
input int    ICH_Shift        = 26;     // 先行スパンの先行本数
input int    ICH_PctBars      = 125;    // 雲の厚みのパーセンタイルに使う過去の本数
input double ICH_ThinPct      = 20.0;   // このパーセンタイル以下を「薄い雲」とする
input int    ICH_FlatBars     = 5;      // 基準線の横ばい判定に使う本数
input double ICH_FlatATR      = 0.20;   // 基準線の変化がATRのこの倍以下なら横ばい
input int    ICH_RecentBars   = 3;      // 雲抜け・TKクロスを「直近」とみなす本数
input double ICH_BreakMarginATR = 0.3;  // 雲抜けとみなす、雲の端からの距離(ATR倍)。雲が薄いと価格が雲を行き来してダマシが出るため
input double ICH_CrossMinATR  = 0.15;   // TKクロスとみなす、転換線と基準線の距離(ATR倍)
input int    ICH_MinRoles     = 2;      // 雲抜け/TKクロスを有効とする、その方向の三役の最低成立数(0=制限なし 3=全部)
input bool   ICH_ShowInList   = true;   // 一覧に一目均衡表の表示を付ける
input bool   ICH_AlertOnCombo = true;   // 圧縮解除と一目の解除方向が重なった時に通知する

struct ICH_Result
  {
   bool   ready;
   double tenkan, kijun;
   double cloudTop, cloudBot;   // 最新の足の位置にある雲(26本前に計算された先行スパン)
   double futA, futB;           // 26本先の雲(いま計算した先行スパン)
   int    pos;                  // 価格と雲の位置: +1=雲の上 0=雲の中 -1=雲の下
   double thickPct;             // 雲の厚み(価格に対する%)
   double thickPctile;          // 雲の厚みのパーセンタイル(低いほど薄い=圧縮)
   bool   thin;                 // 薄い雲(thickPctile <= ICH_ThinPct)
   bool   kijunFlat;            // 基準線が横ばい
   double tkDistATR;            // 転換線と基準線の距離(ATR倍)
   int    tkRel;                // +1=転換線が上 -1=下
   int    chikou;               // +1=遅行スパンが26本前の価格より上 -1=下
   int    bullRoles;            // 三役好転の成立数(0〜3)
   int    bearRoles;            // 三役逆転の成立数(0〜3)
   bool   twistAhead;           // 26本先までに先行スパンのねじれがある
   int    breakDir;             // 直近の雲抜けの向き(+1上抜け -1下抜け 0=なし)
   int    breakAgo;             // その雲抜けが何本前か
   int    crossDir;             // 直近のTKクロスの向き(+1好転 -1逆転 0=なし)
   int    crossAgo;
   int    relDir;               // 「解除の方向」(雲抜けを優先、なければTKクロス)
   int    relKind;              // 1=雲抜け 2=TKクロス 0=なし
   int    relAgo;
   int    score;                // 一目から見た圧縮度(0〜4。CCompressionのScoreとは別)
  };

//--- 配列hl[]のstartからlen本の最高値と最安値の中間
double ICH_Mid(const double &h[], const double &l[], const int start, const int len)
  {
   double hh = h[start];
   double ll = l[start];
   for(int k = 1; k < len; k++)
     {
      if(h[start + k] > hh) hh = h[start + k];
      if(l[start + k] < ll) ll = l[start + k];
     }
   return (hh + ll) / 2.0;
  }

int ICH_Sign(const double v)
  {
   if(v > 0.0) return 1;
   if(v < 0.0) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
bool ICH_Compute(const string symbol, const ENUM_TIMEFRAMES tf, ICH_Result &r)
  {
   r.ready = false;
   r.tenkan = 0; r.kijun = 0; r.cloudTop = 0; r.cloudBot = 0; r.futA = 0; r.futB = 0;
   r.pos = 0; r.thickPct = 0; r.thickPctile = 50.0; r.thin = false; r.kijunFlat = false;
   r.tkDistATR = 0; r.tkRel = 0; r.chikou = 0; r.bullRoles = 0; r.bearRoles = 0;
   r.twistAhead = false; r.breakDir = 0; r.breakAgo = -1; r.crossDir = 0; r.crossAgo = -1;
   r.relDir = 0; r.relKind = 0; r.relAgo = -1; r.score = 0;

   int tn = MathMax(2, ICH_Tenkan);
   int kj = MathMax(tn, ICH_Kijun);
   int sbn = MathMax(kj, ICH_SenkouB);
   int sh = MathMax(1, ICH_Shift);
   int rec = MathMax(1, ICH_RecentBars);
   int pb = MathMax(20, ICH_PctBars);

   // 必要な本数: 雲の厚みを pb+rec+1 本分、各本で「sh本前に計算した先行スパン(sbn本の窓)」が要る
   int need = pb + rec + 2 + sh + sbn + 5;
   double h[], l[], c[];
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   int g1 = CopyHigh(symbol, tf, 1, need, h);
   int g2 = CopyLow(symbol, tf, 1, need, l);
   int g3 = CopyClose(symbol, tf, 1, need, c);
   int got = MathMin(g1, MathMin(g2, g3));
   if(got < need)
      return false;   // 履歴が足りない

   //--- ATR(14本の単純平均) ---
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

   //--- 各足の雲(その足の位置にある雲 = sh本前に計算された先行スパン)と、価格との位置 ---
   int M = pb + rec + 1;   // 0〜M の足について求める
   double top[], bot[], thick[];
   int    pos[];    // 価格と雲の位置(表示・三役用)
   int    posM[];   // 雲の端からマージン以上離れた時だけ雲の外とみなす位置(雲抜けの判定用)
   ArrayResize(top, M + 1);
   ArrayResize(bot, M + 1);
   ArrayResize(thick, M + 1);
   ArrayResize(pos, M + 1);
   ArrayResize(posM, M + 1);
   for(int i = 0; i <= M; i++)
     {
      int j = i + sh;   // その足の雲を作った計算時点
      double a = (ICH_Mid(h, l, j, tn) + ICH_Mid(h, l, j, kj)) / 2.0;
      double b = ICH_Mid(h, l, j, sbn);
      top[i] = MathMax(a, b);
      bot[i] = MathMin(a, b);
      thick[i] = (c[i] != 0.0) ? (top[i] - bot[i]) / c[i] * 100.0 : 0.0;
      pos[i] = (c[i] > top[i]) ? 1 : ((c[i] < bot[i]) ? -1 : 0);
      double mg = ICH_BreakMarginATR * atr;
      posM[i] = (c[i] > top[i] + mg) ? 1 : ((c[i] < bot[i] - mg) ? -1 : 0);
     }

   r.cloudTop = top[0];
   r.cloudBot = bot[0];
   r.pos = pos[0];
   r.thickPct = thick[0];

   //--- 雲の厚みのパーセンタイル(過去pb本の分布の中で、いまの雲がどれだけ薄いか) ---
   int le = 0;
   for(int i = 1; i <= pb; i++)
      if(thick[i] <= thick[0]) le++;
   r.thickPctile = (double)le / (double)pb * 100.0;
   r.thin = (r.thickPctile <= ICH_ThinPct);

   //--- 転換線・基準線 ---
   r.tenkan = ICH_Mid(h, l, 0, tn);
   r.kijun  = ICH_Mid(h, l, 0, kj);
   r.tkRel = ICH_Sign(r.tenkan - r.kijun);
   r.tkDistATR = MathAbs(r.tenkan - r.kijun) / atr;
   double kijunPrev = ICH_Mid(h, l, MathMax(1, ICH_FlatBars), kj);
   r.kijunFlat = (MathAbs(r.kijun - kijunPrev) / atr <= ICH_FlatATR);

   //--- 26本先の雲と、ねじれ(いまの足から26本先までに先行スパンA・Bの上下が入れ替わるか) ---
   r.futA = (ICH_Mid(h, l, 0, tn) + ICH_Mid(h, l, 0, kj)) / 2.0;
   r.futB = ICH_Mid(h, l, 0, sbn);
   int prevSign = 0;
   for(int i = sh; i >= 0; i--)
     {
      double a = (ICH_Mid(h, l, i, tn) + ICH_Mid(h, l, i, kj)) / 2.0;
      double b = ICH_Mid(h, l, i, sbn);
      int sg = ICH_Sign(a - b);
      if(sg != 0)
        {
         if(prevSign != 0 && sg != prevSign)
            r.twistAhead = true;
         prevSign = sg;
        }
     }

   //--- 遅行スパン(いまの終値が、sh本前の終値より上か下か) ---
   r.chikou = ICH_Sign(c[0] - c[sh]);

   //--- 三役 ---
   r.bullRoles = ((r.tkRel > 0) ? 1 : 0) + ((r.pos > 0) ? 1 : 0) + ((r.chikou > 0) ? 1 : 0);
   r.bearRoles = ((r.tkRel < 0) ? 1 : 0) + ((r.pos < 0) ? 1 : 0) + ((r.chikou < 0) ? 1 : 0);

   //--- 直近の雲抜け(最も新しいもの) ---
   for(int k = 0; k < rec; k++)
     {
      if(posM[k] == 1 && posM[k + 1] <= 0)     { r.breakDir = 1;  r.breakAgo = k; break; }
      if(posM[k] == -1 && posM[k + 1] >= 0)    { r.breakDir = -1; r.breakAgo = k; break; }
     }

   //--- 直近のTKクロス(最も新しいもの) ---
   for(int k = 0; k < rec; k++)
     {
      // 転換線と基準線の距離がしきい値以上開いた状態だけを「上/下」とし、近すぎる間は0(どちらでもない)とする
      double thr = ICH_CrossMinATR * atr;
      double d0 = ICH_Mid(h, l, k, tn) - ICH_Mid(h, l, k, kj);
      double d1 = ICH_Mid(h, l, k + 1, tn) - ICH_Mid(h, l, k + 1, kj);
      int s0 = (d0 > thr) ? 1 : ((d0 < -thr) ? -1 : 0);
      int s1 = (d1 > thr) ? 1 : ((d1 < -thr) ? -1 : 0);
      if(s0 > 0 && s1 <= 0) { r.crossDir = 1;  r.crossAgo = k; break; }
      if(s0 < 0 && s1 >= 0) { r.crossDir = -1; r.crossAgo = k; break; }
     }

   //--- 三役がその方向に十分揃っていない雲抜け・TKクロスは、ダマシとして無視する ---
   //--- (保ち合い中は雲が薄く、価格が雲を行き来するだけで雲抜け/TKクロスが頻繁に出るため)
   if(r.breakDir != 0)
     {
      int roles = (r.breakDir > 0) ? r.bullRoles : r.bearRoles;
      if(roles < ICH_MinRoles) { r.breakDir = 0; r.breakAgo = -1; }
     }
   if(r.crossDir != 0)
     {
      int roles = (r.crossDir > 0) ? r.bullRoles : r.bearRoles;
      if(roles < ICH_MinRoles) { r.crossDir = 0; r.crossAgo = -1; }
     }

   //--- 解除の方向(雲抜けを優先) ---
   if(r.breakDir != 0)
     {
      r.relDir = r.breakDir; r.relKind = 1; r.relAgo = r.breakAgo;
     }
   else if(r.crossDir != 0)
     {
      r.relDir = r.crossDir; r.relKind = 2; r.relAgo = r.crossAgo;
     }

   //--- 一目から見た圧縮度(0〜4): 雲の薄さ(0〜2) + 雲の中(1) + 基準線の横ばい(1) ---
   int sc = 0;
   if(r.thickPctile <= ICH_ThinPct)            sc += 2;
   else if(r.thickPctile <= ICH_ThinPct + 15.0) sc += 1;
   if(r.pos == 0)     sc += 1;
   if(r.kijunFlat)    sc += 1;
   r.score = sc;

   r.ready = true;
   return true;
  }

//+------------------------------------------------------------------+
//| 表示・判定・ログ用                                                 |
//+------------------------------------------------------------------+
//--- 解除の方向があるか(雲抜け or TKクロスが直近にある)
bool ICH_HasRelease(const ICH_Result &r)
  {
   return (r.ready && r.relKind != 0);
  }

//--- 解除の方向の短い説明(雲抜け↑ / TK逆転 など)
string ICH_RelText(const ICH_Result &r)
  {
   if(r.relKind == 1) return (r.relDir > 0) ? "雲抜け↑" : "雲抜け↓";
   if(r.relKind == 2) return (r.relDir > 0) ? "TK好転" : "TK逆転";
   return "";
  }

//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string ICH_Text(const ICH_Result &r)
  {
   if(!r.ready)
      return "";
   string t = "";
   if(r.breakDir != 0)
     {
      t += (r.breakDir > 0) ? "雲抜け↑" : "雲抜け↓";
      if(r.breakAgo > 0) t += StringFormat("(%d本前)", r.breakAgo);
     }
   if(r.crossDir != 0)
     {
      if(StringLen(t) > 0) t += " ";
      t += (r.crossDir > 0) ? "TK好転" : "TK逆転";
      if(r.crossAgo > 0) t += StringFormat("(%d本前)", r.crossAgo);
     }
   if(r.bullRoles == 3)      { if(StringLen(t) > 0) t += " "; t += "三役好転"; }
   else if(r.bearRoles == 3) { if(StringLen(t) > 0) t += " "; t += "三役逆転"; }
   if(r.pos == 0 && r.thin)  { if(StringLen(t) > 0) t += " "; t += "薄雲内"; }
   if(r.twistAhead)          { if(StringLen(t) > 0) t += " "; t += "ねじれ先"; }
   if(StringLen(t) == 0)
      return "";
   return "  [一目 " + t + "]";
  }

//--- 検証ログ用の特徴量(ASCIIのみ。カンマは使わない)
string ICH_Feat(const ICH_Result &r)
  {
   if(!r.ready)
      return "ich_ready=0";
   return StringFormat("ich_pos=%d;ich_thick_p=%.0f;ich_thin=%d;ich_flat=%d;ich_tkd=%.2f;ich_rel=%d;ich_kind=%d;ich_ago=%d;ich_bull=%d;ich_bear=%d;ich_chk=%d;ich_twist=%d;ich_score=%d",
                       r.pos, r.thickPctile, r.thin ? 1 : 0, r.kijunFlat ? 1 : 0, r.tkDistATR,
                       r.relDir, r.relKind, r.relAgo, r.bullRoles, r.bearRoles, r.chikou,
                       r.twistAhead ? 1 : 0, r.score);
  }
//+------------------------------------------------------------------+

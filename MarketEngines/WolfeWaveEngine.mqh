//+------------------------------------------------------------------+
//|                                          WolfeWaveEngine.mqh      |
//|  ウォルフ波動エンジン                                              |
//|                                                                    |
//|  確定足だけを使い、直近の5点(ポイント1〜5)からなるウォルフ波動を    |
//|  検出する。強気(買い)と弱気(売り)の両方に対応する。                 |
//|                                                                    |
//|  【成立条件(強気の場合。弱気は上下反転)】                         |
//|   ・ポイント1(安値) 2(高値) 3(安値) 4(高値) が交互に並ぶ            |
//|   ・ポイント3 < ポイント1                                          |
//|   ・ポイント4 < ポイント2、かつ ポイント4 > ポイント1               |
//|   ・1-3ラインと2-4ラインが収束(ウェッジ)し、交点が将来にある        |
//|   ・ポイント5 = ポイント4以降の最安値。ポイント3を割り込み、        |
//|     1-3ラインの延長線も下に超えている(行き過ぎ)                    |
//|   ・ポイント5が直近(WLF_RecentBars本以内)にある                    |
//|  【状態】                                                         |
//|   1=候補  : 行き過ぎている最中                                     |
//|   2=確定  : 最新の確定足の終値が1-3ラインの内側へ戻った            |
//|  【目標】                                                         |
//|   EPA = 1-4ラインを延長した、ETA時点の価格                         |
//|   ETA = 1-3ラインと2-4ラインの交点の時間                           |
//|   (EPA/ETAの定義は解説によって違う。ここでは上記の定義を採用)       |
//|                                                                    |
//|  【位置づけ】                                                     |
//|  ウォルフ波動は、人が目で見て引くパターン。ここでは「スイングを       |
//|  WLF_SwingBars本の左右で決める」という機械的なルールに置き換えて     |
//|  いるので、人が見て引いたものと一致しないことがある。               |
//|  的中率は未検証。検証ログ(WOLFE5など)で確かめる前提。              |
//|  チャートに描画するので、見た目で確認できる。                       |
//+------------------------------------------------------------------+
#property strict

input group "=== ウォルフ波動 ==="
input bool   WLF_Enable          = true;          // ウォルフ波動を計算する
input int    WLF_Lookback        = 250;           // 探す過去の本数
input int    WLF_SwingBars       = 3;             // スイング高値/安値の判定に使う左右の本数
input int    WLF_MinPatternBars  = 12;            // ポイント1〜4に必要な最小の本数
input int    WLF_MaxPatternBars  = 150;           // ポイント1から現在までの最大の本数
input double WLF_MaxOvershootATR = 3.0;           // ポイント5の行き過ぎ幅の上限(ATR倍。大きすぎると単なるブレイク)
input int    WLF_RecentBars      = 2;             // ポイント5を「直近」とみなす本数
input bool   WLF_ShowInList      = true;          // 一覧にウォルフ波動の表示を付ける
input bool   WLF_ListRows        = true;          // 圧縮・急変でなくても、ポイント5確定の行を一覧に出す
input bool   WLF_DrawOnChart     = true;          // 現在のチャートにパターン(ライン・EPA・ETA)を描く
input color  WLF_ColorBuy        = clrDodgerBlue; // 強気(買い)の色
input color  WLF_ColorSell       = clrHotPink;    // 弱気(売り)の色
input bool   WLF_AlertOnWolfe    = false;         // ポイント5確定だけで通知する
input bool   WLF_AlertOnCombo    = true;          // ウォルフ+TD完了(+反転足)が重なった時に通知する

struct WLF_Result
  {
   bool     ready;
   bool     found;       // パターンが成立している
   int      state;       // 1=候補(行き過ぎ中) 2=確定(ラインの内側へ戻って足が確定)
   int      dir;         // +1=強気(買い) -1=弱気(売り)
   int      digits;
   datetime t1, t2, t3, t4, t5;
   double   p1, p2, p3, p4, p5;
   double   atr;         // 基準のATR(14本の単純平均。価格の絶対値)
   double   epa;         // ETA時点での1-4ライン上の価格(目標価格)
   double   epaNow;      // 最新の確定足の位置での1-4ライン上の価格
   int      etaBars;     // 最新の確定足からETAまでの本数(0以下=ETAを過ぎている)
   datetime etaTime;     // ETAの時刻(週末を考慮しない概算)
   double   overshootATR;// ポイント5が1-3ラインを行き過ぎた幅(ATR倍)
   double   rewardATR;   // 最新の終値からEPAまでの距離(ATR倍)
   double   riskATR;     // 最新の終値からポイント5までの距離(ATR倍。損切り目安)
   double   rr;          // rewardATR / riskATR
   int      p5Ago;       // ポイント5が何本前か(0=最新の確定足)
   bool     pinBar;      // 最新の確定足が、期待方向へのピンバー
   bool     engulf;      // 最新の確定足が、期待方向への包み足
  };

//+------------------------------------------------------------------+
//| 検出                                                               |
//+------------------------------------------------------------------+
bool WLF_Compute(const string symbol, const ENUM_TIMEFRAMES tf, WLF_Result &r)
  {
   r.ready = false;  r.found = false;  r.state = 0;  r.dir = 0;  r.digits = 0;
   r.t1 = 0; r.t2 = 0; r.t3 = 0; r.t4 = 0; r.t5 = 0;
   r.p1 = 0; r.p2 = 0; r.p3 = 0; r.p4 = 0; r.p5 = 0;
   r.atr = 0; r.epa = 0; r.epaNow = 0; r.etaBars = 0; r.etaTime = 0;
   r.overshootATR = 0; r.rewardATR = 0; r.riskATR = 0; r.rr = 0; r.p5Ago = -1;
   r.pinBar = false; r.engulf = false;

   int sb = MathMax(1, WLF_SwingBars);
   int N  = MathMax(60, WLF_Lookback) + 2 * sb + 20;

   datetime tm[];
   double o[], h[], l[], c[];
   ArraySetAsSeries(tm, true);
   ArraySetAsSeries(o, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   ArraySetAsSeries(c, true);
   int g0 = CopyTime(symbol, tf, 1, N, tm);
   int g1 = CopyOpen(symbol, tf, 1, N, o);
   int g2 = CopyHigh(symbol, tf, 1, N, h);
   int g3 = CopyLow(symbol, tf, 1, N, l);
   int g4 = CopyClose(symbol, tf, 1, N, c);
   int got = MathMin(g0, MathMin(g1, MathMin(g2, MathMin(g3, g4))));
   if(got < 40)
      return false;

   r.ready = true;   // 計算は成功。パターンの有無は found で表す
   r.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

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
      return true;
   r.atr = atr;

   //--- スイング高値/安値(確定済み: 左右sb本で最高値/最安値)を古い順に並べる ---
   int    pIdx[];
   int    pType[];
   double pPrice[];
   int    pCnt = 0;
   for(int i = got - sb - 1; i >= sb; i--)
     {
      bool isH = true, isL = true;
      for(int j = 1; j <= sb; j++)
        {
         // 新しい側(i-j)は厳密に、古い側(i+j)は同値を許して判定する
         if(h[i] <= h[i - j] || h[i] < h[i + j]) isH = false;
         if(l[i] >= l[i - j] || l[i] > l[i + j]) isL = false;
        }
      if(isH == isL)
         continue;   // 両方・どちらでもない
      int    type  = isH ? 1 : -1;
      double price = isH ? h[i] : l[i];

      if(pCnt > 0 && pType[pCnt - 1] == type)
        {
         // 同じ種類が続いたら、より極端な方だけを残す(高値と安値が交互に並ぶようにする)
         if((type > 0 && price > pPrice[pCnt - 1]) || (type < 0 && price < pPrice[pCnt - 1]))
           {
            pIdx[pCnt - 1]   = i;
            pPrice[pCnt - 1] = price;
           }
        }
      else
        {
         ArrayResize(pIdx,   pCnt + 1);
         ArrayResize(pType,  pCnt + 1);
         ArrayResize(pPrice, pCnt + 1);
         pIdx[pCnt]   = i;
         pType[pCnt]  = type;
         pPrice[pCnt] = price;
         pCnt++;
        }
     }
   if(pCnt < 4)
      return true;

   //--- 直近の4つのスイングをポイント1〜4とする ---
   int ia = pCnt - 4, ib = pCnt - 3, ic = pCnt - 2, id = pCnt - 1;
   int s = pType[id];   // +1: 最後が高値 → 強気(買い)パターン / -1: 最後が安値 → 弱気(売り)パターン

   // 以降は「強気」の形に統一して判定する(弱気は価格の符号を反転して扱う)
   double v1 = s * pPrice[ia], v2 = s * pPrice[ib], v3 = s * pPrice[ic], v4 = s * pPrice[id];
   int    i1 = pIdx[ia], i2 = pIdx[ib], i3 = pIdx[ic], i4 = pIdx[id];

   if(!(v3 < v1 && v4 < v2 && v4 > v1))
      return true;
   if(i1 - i4 < WLF_MinPatternBars)
      return true;
   if(i1 > WLF_MaxPatternBars)
      return true;

   // 横軸は「本数」。新しい足ほど大きい値(最新の確定足=0、過去は負)
   double x1 = -i1, x2 = -i2, x3 = -i3, x4 = -i4;
   double s13 = (v3 - v1) / (x3 - x1);
   double s24 = (v4 - v2) / (x4 - x2);

   //--- 1-3ライン(下)と2-4ライン(上)が収束している(ウェッジ)か ---
   double gap2 = v2 - (v1 + s13 * (x2 - x1));
   double gap4 = v4 - (v1 + s13 * (x4 - x1));
   if(gap4 <= 0.0 || gap4 >= gap2)
      return true;
   double sd = s24 - s13;
   if(sd >= 0.0)
      return true;
   double xs = x2 + gap2 / (-sd);   // 2本のラインの交点(ETA)
   if(xs <= x4)
      return true;

   //--- ポイント5: ポイント4以降の最安値(強気の形に統一済み) ---
   int    i5 = -1;
   double v5 = 1.0e300;
   for(int k = 0; k < i4; k++)
     {
      double lv = (s > 0) ? l[k] : -h[k];
      if(lv < v5) { v5 = lv; i5 = k; }   // 同値なら新しい足を優先
     }
   if(i5 < 0 || i5 >= WLF_RecentBars)
      return true;

   double x5 = -i5;
   double line13_at5 = v1 + s13 * (x5 - x1);
   if(!(v5 < line13_at5 && v5 < v3))
      return true;   // 1-3ラインもポイント3も割り込んでいない
   double ovs = (line13_at5 - v5) / atr;
   if(ovs > WLF_MaxOvershootATR)
      return true;   // 行き過ぎが大きすぎる(単なるブレイクダウン)
   if(xs <= x5)
      return true;   // 交点がポイント5より前

   //--- 最新の確定足がラインの内側へ戻ったか ---
   double closeT0 = s * c[0];
   double line13_at0 = v1 + s13 * (0.0 - x1);
   bool closeInside = (closeT0 > line13_at0);

   //--- 目標(EPA): 1-4ラインを延長した、ETA時点の価格 ---
   double s14 = (v4 - v1) / (x4 - x1);
   double epaT = v1 + s14 * (xs - x1);
   double epaNowT = v1 + s14 * (0.0 - x1);
   if(epaT <= closeT0)
      return true;   // 目標がすでに現在値より手前

   double reward = (epaT - closeT0) / atr;
   double risk   = (closeT0 - v5) / atr;
   if(risk < 0.01) risk = 0.01;

   r.found = true;
   r.state = closeInside ? 2 : 1;
   r.dir   = s;
   r.t1 = tm[i1]; r.t2 = tm[i2]; r.t3 = tm[i3]; r.t4 = tm[i4]; r.t5 = tm[i5];
   r.p1 = pPrice[ia]; r.p2 = pPrice[ib]; r.p3 = pPrice[ic]; r.p4 = pPrice[id];
   r.p5 = (s > 0) ? l[i5] : h[i5];
   r.epa = s * epaT;
   r.epaNow = s * epaNowT;
   r.etaBars = (int)MathRound(xs);
   r.etaTime = tm[0] + (datetime)((long)r.etaBars * PeriodSeconds(tf));
   r.overshootATR = ovs;
   r.rewardATR = reward;
   r.riskATR = risk;
   r.rr = reward / risk;
   r.p5Ago = i5;

   //--- 反転足(最新の確定足が、期待方向へのピンバー/包み足か) ---
   double body = MathAbs(c[0] - o[0]);
   double rng  = h[0] - l[0];
   if(rng > 0.0)
     {
      if(s > 0)
        {
         double lw = MathMin(o[0], c[0]) - l[0];
         r.pinBar = (lw / rng >= 0.6 && body / rng <= 0.3);
         r.engulf = (c[0] > o[0] && c[1] < o[1] && c[0] >= o[1] && o[0] <= c[1]);
        }
      else
        {
         double uw = h[0] - MathMax(o[0], c[0]);
         r.pinBar = (uw / rng >= 0.6 && body / rng <= 0.3);
         r.engulf = (c[0] < o[0] && c[1] > o[1] && c[0] <= o[1] && o[0] >= c[1]);
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| 表示・判定・ログ用                                                 |
//+------------------------------------------------------------------+
bool WLF_IsConfirmed(const WLF_Result &r)
  {
   return (r.ready && r.found && r.state == 2);
  }

//--- 一覧に付ける短い表示。パターンがなければ ""
string WLF_Text(const WLF_Result &r)
  {
   if(!r.ready || !r.found)
      return "";
   string eta = (r.etaBars > 0) ? StringFormat("ETA%d本後", r.etaBars) : "ETA経過";
   string t = StringFormat("Wolfe%s %s EPA%s %s RR%.1f",
                           r.dir > 0 ? "買" : "売", r.state == 2 ? "P5確定" : "P5候補",
                           DoubleToString(r.epa, r.digits), eta, r.rr);
   if(r.pinBar)  t += " ピン";
   if(r.engulf)  t += " 包み";
   return "  [" + t + "]";
  }

//--- 検証ログ用の特徴量(ASCIIのみ。sig=は期待方向。順方向/逆行の集計に使われる)
string WLF_Feat(const WLF_Result &r)
  {
   if(!r.ready || !r.found)
      return "wlf=0";
   return StringFormat("sig=%s;wlf=1;wlf_state=%d;wlf_ovs=%.2f;wlf_rr=%.2f;wlf_reward=%.2f;wlf_risk=%.2f;wlf_eta=%d;wlf_pin=%d;wlf_eng=%d;wlf_p5ago=%d",
                       r.dir > 0 ? "up" : "down", r.state, r.overshootATR, r.rr, r.rewardATR, r.riskATR,
                       r.etaBars, r.pinBar ? 1 : 0, r.engulf ? 1 : 0, r.p5Ago);
  }

//+------------------------------------------------------------------+
//| チャートへの描画(現在のチャートの通貨ペア・時間足のパターン用)    |
//+------------------------------------------------------------------+
string g_wlfDrawKey = "";

void WLF_ClearDrawing()
  {
   if(StringLen(g_wlfDrawKey) == 0)
      return;
   ObjectsDeleteAll(0, "CCOMP_Wolfe_");
   g_wlfDrawKey = "";
  }

void WLF_DrawTrend(const string name, const datetime ta, const double pa,
                   const datetime tb, const double pb, const color clr,
                   const ENUM_LINE_STYLE st, const bool rayRight)
  {
   ObjectCreate(0, name, OBJ_TREND, 0, ta, pa, tb, pb);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

void WLF_DrawLabel(const string name, const datetime t, const double p, const string text,
                   const color clr, const bool above)
  {
   ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, above ? ANCHOR_LOWER : ANCHOR_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//--- パターンを描く。同じパターンなら描き直さない(ちらつき防止)
void WLF_DrawPattern(const WLF_Result &r)
  {
   if(!r.ready || !r.found)
     {
      WLF_ClearDrawing();
      return;
     }
   string key = StringFormat("%I64d_%d_%d", (long)r.t5, r.state, r.dir);
   if(key == g_wlfDrawKey)
      return;

   ObjectsDeleteAll(0, "CCOMP_Wolfe_");
   g_wlfDrawKey = key;

   color clr = (r.dir > 0) ? WLF_ColorBuy : WLF_ColorSell;
   // 1-3ライン(実線・右へ延長) / 2-4ライン(実線・右へ延長) / 1-4ライン=目標(破線・右へ延長)
   WLF_DrawTrend("CCOMP_Wolfe_L13", r.t1, r.p1, r.t3, r.p3, clr, STYLE_SOLID, true);
   WLF_DrawTrend("CCOMP_Wolfe_L24", r.t2, r.p2, r.t4, r.p4, clr, STYLE_SOLID, true);
   WLF_DrawTrend("CCOMP_Wolfe_L14", r.t1, r.p1, r.t4, r.p4, clr, STYLE_DASH, true);

   // ポイントの番号(強気は 1,3,5=安値 / 2,4=高値。弱気は逆)
   datetime ts[5];
   double   ps[5];
   ts[0] = r.t1; ts[1] = r.t2; ts[2] = r.t3; ts[3] = r.t4; ts[4] = r.t5;
   ps[0] = r.p1; ps[1] = r.p2; ps[2] = r.p3; ps[3] = r.p4; ps[4] = r.p5;
   for(int k = 0; k < 5; k++)
     {
      bool isLow = (r.dir > 0) ? (k % 2 == 0) : (k % 2 == 1);
      WLF_DrawLabel("CCOMP_Wolfe_P" + IntegerToString(k + 1), ts[k], ps[k], IntegerToString(k + 1), clr, !isLow);
     }

   // ETA(縦線)とEPA(目標価格)
   ObjectCreate(0, "CCOMP_Wolfe_ETA", OBJ_VLINE, 0, r.etaTime, 0);
   ObjectSetInteger(0, "CCOMP_Wolfe_ETA", OBJPROP_COLOR, clr);
   ObjectSetInteger(0, "CCOMP_Wolfe_ETA", OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, "CCOMP_Wolfe_ETA", OBJPROP_BACK, true);
   ObjectSetInteger(0, "CCOMP_Wolfe_ETA", OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, "CCOMP_Wolfe_ETA", OBJPROP_HIDDEN, true);
   WLF_DrawLabel("CCOMP_Wolfe_EPA", r.etaTime, r.epa,
                 "EPA " + DoubleToString(r.epa, r.digits), clr, (r.dir > 0));
  }
//+------------------------------------------------------------------+

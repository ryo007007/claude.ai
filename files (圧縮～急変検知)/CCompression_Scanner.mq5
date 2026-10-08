//+------------------------------------------------------------------+
//|                                     CCompression_Scanner.mq5      |
//|  複数通貨ペア × 複数時間足のCCompression状態を一覧表示するスキャナー |
//|                                                                    |
//|  ・Compression状態(NORMAL以外)の銘柄/時間足のみ表示                |
//|  ・圧縮が強い順(TRANSITION優先 → Score降順)にソート                |
//|  ・行をクリックするとその通貨ペア・時間足にチャートが切り替わる    |
//|                                                                    |
//|  まずはこのスタンドアロン版で検証し、問題なければMTF_TrendSign     |
//|  パネルへの統合を検討する。                                        |
//+------------------------------------------------------------------+
#property copyright "CCompression scanner"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include "CCompression.mqh"
#include "SuddenMoveDetector.mqh"   // 急変検知(SMD_CheckSpike)を使用

//---------------- 入力パラメータ ----------------
input string InpSymbols = "USDJPY,EURUSD,GBPUSD,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,AUDJPY,NZDJPY,CADJPY,CHFJPY,EURGBP,GBPCHF,EURCAD,EURCHF,AUDNZD,CADCHF,AUDCHF,GBPCAD,AUDCAD,EURAUD,GBPAUD,EURNZD,XAUUSD,BTCUSD";

input group "=== 監視する時間足 ==="
input bool ScanD1  = true;  // 日足
input bool ScanH4  = true;  // 4時間足
input bool ScanH1  = true;  // 1時間足
input bool ScanM30 = true;  // 30分足
input bool ScanM15 = true;  // 15分足
input bool ScanM5  = false; // 5分足（監視対象が多いと重くなるのでデフォルトOFF）
input bool ScanM1  = false; // 1分足（同上）

input group "=== 表示設定 ==="
input int  PanelX           = 10;   // パネルX座標
input int  PanelY           = 20;   // パネルY座標
input int  MaxRows          = 40;   // 最大表示行数
input int  RefreshSeconds   = 1;    // 再計算の最小間隔(秒)
input bool OpenInNewChart   = false; // trueなら新規チャート、falseなら現在のチャートを切替

input group "=== 表示する最低状態 ==="
input bool ShowCompression       = true; // COMPRESSION以上を表示
input bool ShowOnlyStrongOrAbove = false; // trueならSTRONG COMPRESSION以上のみ表示
input bool ShowTransition        = true; // TRANSITION(圧縮解除中)を表示

input group "=== 急変検知との連携 ==="
input bool UseSpikeOverride  = true;  // 急変を検知したら圧縮表示を解除して「急変」として表示する
input int  SpikeHoldBars     = 3;     // 急変表示を保持する本数(その時間足の本数)
input bool SpikeShowAlways   = false; // trueなら圧縮中でない行の急変も表示(falseは圧縮中の行のみ対象)
input color SpikeUpColor     = clrLime;      // 急変(上昇)の表示色
input color SpikeDownColor   = clrDeepPink;  // 急変(下落)の表示色

//---------------- グローバル ----------------
string          g_symbols[];
int             g_symbolCount = 0;
ENUM_TIMEFRAMES g_tfList[];
int             g_tfCount = 0;

CCOMP_Instance  g_scan[];     // symbolCount * tfCount 分のインスタンス
int             g_scanTotal = 0;

// 現在表示中の行がどの(symbol, tf)に対応するか（クリック処理用。描画のたびに更新）
string          g_rowSymbol[];
ENUM_TIMEFRAMES g_rowTF[];
int             g_rowCount = 0;

// (通貨ペア×時間足)ごとの急変状態。g_scanと同じインデックスで対応する
datetime        g_spikeUntil[];   // この時刻までは「急変」として表示する
bool            g_spikeUp[];      // 急変の方向(true=上昇)
double          g_spikeRatio[];   // 急変検知時のATR比
double          g_spikeZ[];       // 急変検知時のROC Zスコア
bool            g_suppressed[];   // 急変で圧縮表示を解除済み(圧縮がNORMALに戻るまで非表示)

//+------------------------------------------------------------------+
int ParseSymbols(string src, string &outArr[])
  {
   string raw[];
   int n = StringSplit(src, ',', raw);
   int count = 0;
   ArrayResize(outArr, n);
   for(int i = 0; i < n; i++)
     {
      string s = raw[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      outArr[count] = s;
      count++;
     }
   ArrayResize(outArr, count);
   return count;
  }

//+------------------------------------------------------------------+
color CCOMP_StateColor(const CCOMP_STATE st)
  {
   switch(st)
     {
      case CCOMP_COMPRESSION:        return clrYellow;
      case CCOMP_STRONG_COMPRESSION: return clrOrange;
      case CCOMP_TIGHT_COMPRESSION:  return clrRed;
      case CCOMP_TRANSITION:         return clrAqua;
      default:                       return clrWhite;
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_symbolCount = ParseSymbols(InpSymbols, g_symbols);

   ENUM_TIMEFRAMES tmp[];
   ArrayResize(tmp, 7);
   int c = 0;
   if(ScanD1)  tmp[c++] = PERIOD_D1;
   if(ScanH4)  tmp[c++] = PERIOD_H4;
   if(ScanH1)  tmp[c++] = PERIOD_H1;
   if(ScanM30) tmp[c++] = PERIOD_M30;
   if(ScanM15) tmp[c++] = PERIOD_M15;
   if(ScanM5)  tmp[c++] = PERIOD_M5;
   if(ScanM1)  tmp[c++] = PERIOD_M1;
   g_tfCount = c;
   ArrayResize(g_tfList, c);
   for(int i = 0; i < c; i++) g_tfList[i] = tmp[i];

   if(g_symbolCount == 0 || g_tfCount == 0)
     {
      Print("CCompression_Scanner: 監視対象の通貨ペアまたは時間足が0件です");
      return(INIT_FAILED);
     }

   g_scanTotal = g_symbolCount * g_tfCount;
   ArrayResize(g_scan, g_scanTotal);

   ArrayResize(g_spikeUntil, g_scanTotal);
   ArrayResize(g_spikeUp,    g_scanTotal);
   ArrayResize(g_spikeRatio, g_scanTotal);
   ArrayResize(g_spikeZ,     g_scanTotal);
   ArrayResize(g_suppressed, g_scanTotal);
   for(int k = 0; k < g_scanTotal; k++)
     {
      g_spikeUntil[k] = 0;
      g_spikeUp[k]    = false;
      g_spikeRatio[k] = 0.0;
      g_spikeZ[k]     = 0.0;
      g_suppressed[k] = false;
     }

   for(int si = 0; si < g_symbolCount; si++)
      for(int ti = 0; ti < g_tfCount; ti++)
        {
         int idx = si * g_tfCount + ti;
         if(!CCOMP_InitInstance(g_scan[idx], g_symbols[si], g_tfList[ti]))
            PrintFormat("初期化失敗: %s %s", g_symbols[si], EnumToString(g_tfList[ti]));
        }

   EventSetTimer(MathMax(1, RefreshSeconds));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_scanTotal; i++)
      CCOMP_ReleaseInstance(g_scan[i]);
   ObjectsDeleteAll(0, "CCOMP_Scan_");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| 表示対象とすべき状態かどうかを入力設定に従って判定                 |
//+------------------------------------------------------------------+
bool ShouldDisplay(const CCOMP_STATE st)
  {
   if(st == CCOMP_NORMAL) return false;
   if(st == CCOMP_TRANSITION) return ShowTransition;
   if(ShowOnlyStrongOrAbove)
      return (st == CCOMP_STRONG_COMPRESSION || st == CCOMP_TIGHT_COMPRESSION);
   return ShowCompression; // COMPRESSION / STRONG / TIGHT すべて含む
  }

//+------------------------------------------------------------------+
//| 行の表示用ラベルを作成/更新                                        |
//+------------------------------------------------------------------+
void DrawRow(const int r, const string text, const color clr)
  {
   string name = "CCOMP_Scan_Row_" + IntegerToString(r);
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, PanelY + 18 + r * 14);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| 全インスタンス更新 → フィルタ・ソート → 描画                      |
//+------------------------------------------------------------------+
void UpdateAndDraw()
  {
   for(int i = 0; i < g_scanTotal; i++)
      CCOMP_UpdateInstance(g_scan[i]);

   //--- 急変検知(圧縮中の行が対象。SpikeShowAlways=trueなら全行) ---
   datetime nowT = TimeCurrent();
   if(UseSpikeOverride)
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready) continue;

         // 圧縮が一度NORMALに戻ったら抑制を解除(次に圧縮が再形成されたら再び表示する)
         if(g_suppressed[i] && g_scan[i].state == CCOMP_NORMAL)
            g_suppressed[i] = false;

         if(g_scan[i].state == CCOMP_NORMAL && !SpikeShowAlways) continue;

         bool isSp, isUp;
         double ratio, z;
         if(!SMD_CheckSpike(g_scan[i].symbol, g_scan[i].tf, g_scan[i].atrHandle, isSp, isUp, ratio, z))
            continue;

         if(isSp)
           {
            g_spikeUntil[i] = nowT + SpikeHoldBars * PeriodSeconds(g_scan[i].tf);
            g_spikeUp[i]    = isUp;
            g_spikeRatio[i] = ratio;
            g_spikeZ[i]     = z;
            // 圧縮中だった行は、急変で圧縮表示を解除(NORMALに戻るまで圧縮としては出さない)
            if(g_scan[i].state != CCOMP_NORMAL)
               g_suppressed[i] = true;
           }
        }
     }

   //--- フィルタして対象indexと優先度キーを収集 ---
   int    candIdx[];
   double candKey[];
   int    candKind[];   // 0=圧縮表示 / 1=急変表示
   ArrayResize(candIdx, g_scanTotal);
   ArrayResize(candKey, g_scanTotal);
   ArrayResize(candKind, g_scanTotal);
   int n = 0;
   int nSpike = 0;
   for(int i = 0; i < g_scanTotal; i++)
     {
      if(!g_scan[i].ready) continue;

      // 急変表示(最優先)。保持期間中は圧縮表示の代わりにこちらを出す
      if(UseSpikeOverride && nowT < g_spikeUntil[i])
        {
         candIdx[n]  = i;
         candKind[n] = 1;
         candKey[n]  = 200.0 + MathMin(g_spikeRatio[i], 50.0);
         n++;
         nSpike++;
         continue;
        }

      // 急変で圧縮表示を解除された行は、圧縮がNORMALに戻るまで出さない
      if(UseSpikeOverride && g_suppressed[i]) continue;

      if(!ShouldDisplay(g_scan[i].state)) continue;
      candIdx[n]  = i;
      candKind[n] = 0;
      // TRANSITIONは圧縮表示の中で最優先、それ以外はScoreの高い順
      candKey[n]  = (g_scan[i].state == CCOMP_TRANSITION) ? (100.0 + g_scan[i].score) : (double)g_scan[i].score;
      n++;
     }

   //--- 優先度キー降順にソート(単純選択ソート。件数は多くても数百件程度なので十分) ---
   for(int a = 0; a < n - 1; a++)
     {
      int best = a;
      for(int b = a + 1; b < n; b++)
        {
         if(candKey[b] > candKey[best])
            best = b;
         else if(candKey[b] == candKey[best])
           {
            // 同順位なら短い時間足を上段に、時間足も同じなら通貨ペア名順
            int pb = PeriodSeconds(g_scan[candIdx[b]].tf);
            int pBest = PeriodSeconds(g_scan[candIdx[best]].tf);
            if(pb < pBest)
               best = b;
            else if(pb == pBest && g_scan[candIdx[b]].symbol < g_scan[candIdx[best]].symbol)
               best = b;
           }
        }
      if(best != a)
        {
         double tk = candKey[a];  candKey[a]  = candKey[best];  candKey[best]  = tk;
         int    ti = candIdx[a];  candIdx[a]  = candIdx[best];  candIdx[best]  = ti;
         int    tn = candKind[a]; candKind[a] = candKind[best]; candKind[best] = tn;
        }
     }

   int shown = MathMin(n, MaxRows);

   //--- タイトル行 ---
   string title = StringFormat("CCompression Scanner  (圧縮%d件 急変%d件 / 全%d組)", n - nSpike, nSpike, g_scanTotal);
   {
      string tname = "CCOMP_Scan_Title";
      if(ObjectFind(0, tname) < 0)
        {
         ObjectCreate(0, tname, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, tname, OBJPROP_FONTSIZE, 10);
         ObjectSetString(0, tname, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, tname, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, tname, OBJPROP_BACK, false);
         ObjectSetInteger(0, tname, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, tname, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        }
      ObjectSetInteger(0, tname, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, tname, OBJPROP_YDISTANCE, PanelY);
      ObjectSetString(0, tname, OBJPROP_TEXT, title);
      ObjectSetInteger(0, tname, OBJPROP_COLOR, clrWhite);
   }
   //--- 既存行を一旦全削除してから再構築(件数が増減するため) ---
   ObjectsDeleteAll(0, "CCOMP_Scan_Row_");
   ArrayResize(g_rowSymbol, shown);
   ArrayResize(g_rowTF, shown);
   g_rowCount = shown;

   for(int r = 0; r < shown; r++)
     {
      int idx = candIdx[r];
      CCOMP_Instance inst = g_scan[idx];

      string tfName = EnumToString(inst.tf);
      StringReplace(tfName, "PERIOD_", "");

      string line;
      color  rowClr;
      if(candKind[r] == 1)
        {
         // 急変表示: 圧縮表示の代わりに方向つきで表示する
         line = StringFormat("%-9s %-4s %-20s ATR比%.1f Z%+.1f",
            inst.symbol, tfName, g_spikeUp[idx] ? "急変 ↑ (上昇)" : "急変 ↓ (下落)",
            g_spikeRatio[idx], g_spikeZ[idx]);
         rowClr = g_spikeUp[idx] ? SpikeUpColor : SpikeDownColor;
        }
      else
        {
         line = StringFormat("%-9s %-4s %-20s Sc%d Δ%+d Age%d",
            inst.symbol, tfName, CCOMP_StateText(inst.state), inst.score, inst.delta, inst.age);
         rowClr = CCOMP_StateColor(inst.state);
        }

      DrawRow(r, line, rowClr);

      g_rowSymbol[r] = inst.symbol;
      g_rowTF[r]     = inst.tf;
     }

   if(n > shown)
     {
      string moreName = "CCOMP_Scan_More";
      if(ObjectFind(0, moreName) < 0)
        {
         ObjectCreate(0, moreName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, moreName, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, moreName, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, moreName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, moreName, OBJPROP_BACK, false);
         ObjectSetInteger(0, moreName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, moreName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
        }
      ObjectSetInteger(0, moreName, OBJPROP_XDISTANCE, PanelX);
      ObjectSetInteger(0, moreName, OBJPROP_YDISTANCE, PanelY + 18 + shown * 14);
      ObjectSetString(0, moreName, OBJPROP_TEXT, StringFormat("...他 %d件", n - shown));
      ObjectSetInteger(0, moreName, OBJPROP_COLOR, clrGray);
     }
   else
      ObjectDelete(0, "CCOMP_Scan_More");

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                 const datetime &time[], const double &open[], const double &high[],
                 const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
  {
   UpdateAndDraw();
   return(rates_total);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateAndDraw();
  }

//+------------------------------------------------------------------+
//| 行クリックでその通貨ペア・時間足にチャートを切り替える             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   string prefix = "CCOMP_Scan_Row_";
   if(StringFind(sparam, prefix) != 0) return;

   string idxStr = StringSubstr(sparam, StringLen(prefix));
   int r = (int)StringToInteger(idxStr);
   if(r < 0 || r >= g_rowCount) return;

   string sym          = g_rowSymbol[r];
   ENUM_TIMEFRAMES tf   = g_rowTF[r];

   if(OpenInNewChart)
     {
      long newChartId = ChartOpen(sym, tf);
      if(newChartId == 0) Print("チャートを開けませんでした: ", sym);
     }
   else
     {
      bool ok = ChartSetSymbolPeriod(0, sym, tf);
      if(!ok) Print("通貨ペア/時間足の切り替えに失敗しました: ", sym, " ", EnumToString(tf));
     }
  }
//+------------------------------------------------------------------+

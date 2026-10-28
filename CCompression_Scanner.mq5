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

#include "MarketEngines/CCompression.mqh"        // 圧縮検出エンジン
#include "MarketEngines/SuddenMoveDetector.mqh"  // 急変検知エンジン
#include "MarketEngines/SignalAlert.mqh"         // アラートエンジン
#include "MarketEngines/SignalLogger.mqh"        // 結果記録エンジン
#include "MarketEngines/EventTimeEngine.mqh"       // 指標発表・市場開場エンジン
#include "MarketEngines/RelatedPairEngine.mqh"     // 関連通貨エンジン(予兆スコア)
#include "MarketEngines/TDSequentialEngine.mqh"    // TDシーケンシャルエンジン
#include "MarketEngines/WolfeWaveEngine.mqh"        // ウォルフ波動エンジン
#include "MarketEngines/IchimokuEngine.mqh"          // 一目均衡表エンジン
#include "MarketEngines/WickDetector.mqh"        // 髭検知エンジン（追加）

//---------------- 入力パラメータ ----------------
input string InpSymbols = "USDJPY,EURUSD,GBPUSD,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,AUDJPY,NZDJPY,CADJPY,CHFJPY,EURGBP,GBPCHF,EURCAD,EURCHF,AUDNZD,CADCHF,AUDCHF,GBPCAD,AUDCAD,EURAUD,GBPAUD,EURNZD,GOLD,BTCUSD,US30Cash,Nasdaq";

input group "=== 監視する時間足 ==="
input bool ScanD1  = false;  // 日足
input bool ScanH4  = true;  // 4時間足
input bool ScanH1  = true;  // 1時間足
input bool ScanM30 = true;  // 30分足
input bool ScanM15 = true;  // 15分足
input bool ScanM5  = true;  // 5分足（銘柄が多く重い場合はOFF）
input bool ScanM1  = false; // 1分足（同上）

input group "=== 表示設定 ==="
input int  PanelX           = 10;   // パネルX座標
input int  PanelY           = 20;   // パネルY座標
input int  MaxRows          = 40;   // 最大表示行数
input int  RefreshSeconds   = 1;    // 再計算の最小間隔(秒)
input bool OpenInNewChart   = false; // trueなら新規チャート、falseなら現在のチャートを切替

input group "=== 検証パネル(結果記録の集計) ==="
input bool ShowStatsPanel  = true;   // 起動時に検証パネルを表示する(ボタンで随時切替可)
input int  StatsX          = 130;     // 右上からのX距離
input int  StatsY          = 20;     // 右上からのY距離

input group "=== 予兆スコア・指標の表示 ==="
input bool ShowImminenceInList = true;   // 一覧に予兆スコア(%)を表示する
input bool ShowEventInList     = true;   // 一覧に次の指標・開場までの時間を表示する
input bool SortByImminence     = false;  // trueなら、圧縮表示を予兆スコアの高い順に並べる(falseは圧縮Score順)

input group "=== 解説パネル(現在のチャートの通貨・時間足) ==="
input bool ShowDetailPanel = true;               // 解説パネルを表示する
input ENUM_BASE_CORNER DetailCorner = CORNER_LEFT_LOWER; // 表示する隅
input int  DetailX         = 500;                // 隅からのX距離
input int  DetailY         = 20;                 // 隅からのY距離

input group "=== 表示する最低状態 ==="
input bool ShowCompression       = true; // COMPRESSION以上を表示
input bool ShowOnlyStrongOrAbove = false; // trueならSTRONG COMPRESSION以上のみ表示
input bool ShowTransition        = true; // TRANSITION(圧縮解除中)を表示

input group "=== 急変検知との連携 ==="
input bool UseSpikeOverride  = true;  // 急変を検知したら圧縮表示を解除して「急変」として表示する
input int  SpikeHoldBars     = 3;     // 急変表示を保持する本数(その時間足の本数)
input bool SpikeShowAlways   = false; // trueなら圧縮中でない行の急変も表示(falseは圧縮中の行のみ対象)
input bool UseSpikeV2        = true;  // 精度改善版(V2)の急変判定を使う(falseなら従来のV1)
input color SpikeUpColor     = clrLime;      // 急変(上昇)の表示色
input color SpikeDownColor   = clrDeepPink;  // 急変(下落)の表示色

input group "=== 髭（WICK）検知 ==="
input bool   UseWickDetector  = true;    // 髭検知を有効にする
input double WickRangeMult    = 3.0;     // 値幅倍率閾値（中央値の何倍か）
input double WickMinRatio     = 0.60;    // 髭割合閾値（0.50=50%, 0.60=60%）
input bool   WickScanM1       = true;    // 1分足も髭検知対象にする（圧縮監視とは独立）
input int    WickMaxHistory   = 30;      // 髭検知履歴の最大保持件数
input int    WickLookbackBars = 100;     // 再起動時に遡る足数
input bool   WickAlertOn      = true;    // 髭検知時にアラートを出す

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

// 画面のON/OFF状態(ボタンで切替。チャート切替で読み込み直されても、端末のグローバル変数で引き継ぐ)
bool            g_logOn   = true;   // 検証ログを記録するか
bool            g_statsOn = true;   // 検証パネルを表示するか

// 予兆スコア計算用(添字は 時間足番号*銘柄数 + 銘柄番号)
int             g_immScore[];
bool            g_immAct[];
bool            g_immUp[];

// TDシーケンシャルの結果(g_scanと同じ添字)と、最後に計算した確定足の時刻
TDS_Result      g_td[];
datetime        g_tdBar[];

// ウォルフ波動の結果(g_scanと同じ添字)と、最後に計算した確定足の時刻
WLF_Result      g_wlf[];
datetime        g_wlfBar[];

// 一目均衡表の結果(g_scanと同じ添字)と、最後に計算した確定足の時刻
ICH_Result      g_ich[];
datetime        g_ichBar[];

//--- 髭検知用
ENUM_TIMEFRAMES g_wickTfList[];
int             g_wickTfCount = 0;

struct WICK_HistoryItem
{
   string          symbol;
   ENUM_TIMEFRAMES tf;
   datetime        barTime;      // 検知した足の時刻
   bool            isUpper;
   double          wickRatio;
   double          multiplier;
};
WICK_HistoryItem  g_wickHistory[];
int               g_wickHistoryCount = 0;

// 基準(対照)を最後に判定した確定足の時刻(g_scanと同じ添字)
datetime        g_baseBar[];

void DrawDetailPanel();   // 解説パネル描画(定義はファイル末尾)
void DrawStatsPanel();    // 検証パネル描画(定義はファイル末尾)
void DrawWickPanel();   // 髭検知パネル描画
void DrawWolfeChart();    // ウォルフ波動のチャート描画(定義はファイル末尾)

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
//+------------------------------------------------------------------+
//| 急変状態の保存・復元                                               |
//| 行クリックでチャートの通貨/時間足が変わるとインジケーターが         |
//| 読み込み直されるため、急変の保持状態を端末のグローバル変数に        |
//| 保存して引き継ぐ。                                                 |
//+------------------------------------------------------------------+
string TFName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
  }

//--- 行(インスタンス番号idx)の予兆スコアと、指標・開場情報を計算する
void ComputeRowImminence(const int idx, REL_Result &rr, EVT_Info &ev)
  {
   EVT_GetInfo(g_scan[idx].symbol, PeriodSeconds(g_scan[idx].tf), ev);
   int si = idx / g_tfCount;
   int ti = idx % g_tfCount;
   REL_Compute(si, ti, g_immScore, g_immAct, g_immUp, g_scan[idx].score, ev.score, rr);
  }

//--- 一覧用の短い指標・開場表示
string EventShort(const EVT_Info &ev)
  {
   if(ev.minToNext >= 0 && ev.minToNext <= 360)
      return StringFormat("  [%s指標 %d分後]", ev.nextCur, ev.minToNext);
   if(ev.minToSession >= 0 && ev.minToSession <= 120)
      return StringFormat("  [%s開場 %d分後]", ev.sessionName, ev.minToSession);
   return "";
  }

string GVKey(const int i, const string field)
  {
   return "CCOMP_" + field + "_" + g_scan[i].symbol + "_" + IntegerToString(PeriodSeconds(g_scan[i].tf));
  }

void SaveSpikeState(const int i)
  {
   GlobalVariableSet(GVKey(i, "SU"), (double)g_spikeUntil[i]);
   GlobalVariableSet(GVKey(i, "SD"), g_spikeUp[i] ? 1.0 : 0.0);
   GlobalVariableSet(GVKey(i, "SR"), g_spikeRatio[i]);
   GlobalVariableSet(GVKey(i, "SZ"), g_spikeZ[i]);
  }

void SaveSuppressed(const int i, const bool on)
  {
   string k = GVKey(i, "SP");
   if(on)
      GlobalVariableSet(k, 1.0);
   else if(GlobalVariableCheck(k))
      GlobalVariableDel(k);
  }

//--- 同じ行・同じ種類のイベントを、続けて記録しない(連続する急変を1つの急変として数える)
//--- 検知が続いている間は、期限を延ばし続ける。検知が SpikeHoldBars 本の間途切れた時に初めて、次の急変として記録する。
//--- (期限を延ばさないと、長く続く急変を SpikeHoldBars 本ごとに何度も記録してしまう)
//--- 端末のグローバル変数に期限を保存するので、チャートの切替で読み込み直されても重複しない
bool EpisodeFire(const int i, const string field, const datetime now)
  {
   string key = GVKey(i, field);
   bool active = (GlobalVariableCheck(key) && GlobalVariableGet(key) > (double)now);
   GlobalVariableSet(key, (double)(now + (datetime)(SpikeHoldBars * PeriodSeconds(g_scan[i].tf))));
   return !active;
  }

void LoadSpikeStates()
  {
   datetime now = TimeCurrent();
   for(int i = 0; i < g_scanTotal; i++)
     {
      string ku = GVKey(i, "SU");
      if(GlobalVariableCheck(ku))
        {
         datetime until = (datetime)(long)GlobalVariableGet(ku);
         if(until > now)
           {
            g_spikeUntil[i] = until;
            g_spikeUp[i]    = (GlobalVariableGet(GVKey(i, "SD")) > 0.5);
            g_spikeRatio[i] = GlobalVariableGet(GVKey(i, "SR"));
            g_spikeZ[i]     = GlobalVariableGet(GVKey(i, "SZ"));
           }
         else
           {
            // 期限切れは削除
            GlobalVariableDel(ku);
            GlobalVariableDel(GVKey(i, "SD"));
            GlobalVariableDel(GVKey(i, "SR"));
            GlobalVariableDel(GVKey(i, "SZ"));
           }
        }
      if(GlobalVariableCheck(GVKey(i, "SP")))
         g_suppressed[i] = true;
     }
  }

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
   
   //--- 検知用時間足リストの作成（圧縮監視とは独立。M1はWickScanM1に従う）
   ArrayResize(g_wickTfList, 7);
   int wc = 0;
   if(ScanD1)  g_wickTfList[wc++] = PERIOD_D1;
   if(ScanH4)  g_wickTfList[wc++] = PERIOD_H4;
   if(ScanH1)  g_wickTfList[wc++] = PERIOD_H1;
   if(ScanM30) g_wickTfList[wc++] = PERIOD_M30;
   if(ScanM15) g_wickTfList[wc++] = PERIOD_M15;
   if(ScanM5)  g_wickTfList[wc++] = PERIOD_M5;
   if(WickScanM1) g_wickTfList[wc++] = PERIOD_M1; // 圧縮監視とは独立
   g_wickTfCount = wc;
   ArrayResize(g_wickTfList, wc);
   ArrayResize(g_wickHistory, WickMaxHistory);
   
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
   ArrayResize(g_td,    g_scanTotal);
   ArrayResize(g_tdBar, g_scanTotal);
   ArrayResize(g_wlf,    g_scanTotal);
   ArrayResize(g_wlfBar, g_scanTotal);
   ArrayResize(g_ich,    g_scanTotal);
   ArrayResize(g_ichBar, g_scanTotal);
   ArrayResize(g_baseBar, g_scanTotal);
   for(int tk = 0; tk < g_scanTotal; tk++)
     {
      g_tdBar[tk]      = 0;
      g_td[tk].ready   = false;
      g_td[tk].recent  = false;
      g_wlfBar[tk]     = 0;
      g_wlf[tk].ready  = false;
      g_wlf[tk].found  = false;
      g_ichBar[tk]     = 0;
      g_ich[tk].ready  = false;
      g_baseBar[tk]    = 0;
     }
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

   REL_Init(g_symbols, g_symbolCount, g_tfList, g_tfCount);   // 関連通貨エンジン

   SLG_Init();          // 結果記録の初期化(過去のログを読み込む)
   // 画面のON/OFF状態を復元(なければ入力パラメータの値)
   g_logOn   = GlobalVariableCheck("CCOMP_UI_LOG")   ? (GlobalVariableGet("CCOMP_UI_LOG")   > 0.5) : SLG_Enable;
   g_statsOn = GlobalVariableCheck("CCOMP_UI_STATS") ? (GlobalVariableGet("CCOMP_UI_STATS") > 0.5) : ShowStatsPanel;
   SLG_SetOn(g_logOn);
   LoadSpikeStates();   // チャート切替で読み込み直された場合に急変状態を引き継ぐ
   
   // =========================================================================
   // 【追加】再起動時に過去の髭を検知してパネルに表示する処理
   // =========================================================================
   if(UseWickDetector && WickLookbackBars > 0)
     {
      // 一時配列を用意（古い順に格納する）
      int tempCount = 0;
      int maxTemp = WickLookbackBars * g_symbolCount * g_wickTfCount;
      WICK_HistoryItem tempHistory[];
      ArrayResize(tempHistory, maxTemp);

      // 古い足（WickLookbackBars本前）から新しい足（2本前）に向かってループ
      for(int shift = WickLookbackBars; shift >= 2; shift--)
        {
         for(int si = 0; si < g_symbolCount; si++)
           {
            for(int ti = 0; ti < g_wickTfCount; ti++)
              {
               string sym = g_symbols[si];
               ENUM_TIMEFRAMES tf = g_wickTfList[ti];
               
               WICK_Info wick;
               // shift本前の足をチェック
               if(!WICK_Check(sym, tf, shift, WickRangeMult, WickMinRatio, wick)) continue;
               
               datetime barTime = iTime(sym, tf, shift);
               
               tempHistory[tempCount].symbol    = sym;
               tempHistory[tempCount].tf        = tf;
               tempHistory[tempCount].barTime   = barTime;
               tempHistory[tempCount].isUpper   = wick.isUpper;
               tempHistory[tempCount].wickRatio = wick.wickRatio;
               tempHistory[tempCount].multiplier = wick.multiplier;
               tempCount++;
              }
           }
        }

      // 一時配列（古い順）を、g_wickHistory（最新が先頭）に変換して格納
      g_wickHistoryCount = 0;
      ArrayResize(g_wickHistory, WickMaxHistory);
      
      // 配列の末尾（最新）から先頭に向かって g_wickHistory に詰める
      for(int i = tempCount - 1; i >= 0 && g_wickHistoryCount < WickMaxHistory; i--)
        {
         g_wickHistory[g_wickHistoryCount] = tempHistory[i];
         g_wickHistoryCount++;
        }
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
   ObjectsDeleteAll(0, "CCOMP_Wick_");
   g_wlfDrawKey = "x";      // 描画キーを無効化してから削除する
   WLF_ClearDrawing();
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
   datetime nowT = TimeCurrent();

   for(int i = 0; i < g_scanTotal; i++)
      CCOMP_UpdateInstance(g_scan[i]);

   //--- 指標カレンダー・相関係数の更新(内部で間隔を空けて実行される) ---
   EVT_Refresh();
   REL_Update();

   //--- TDシーケンシャル(確定足が更新された行だけ計算する) ---
   if(TDS_Enable)
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready || g_scan[i].lastBarTime == g_tdBar[i]) continue;
         if(TDS_Compute(g_scan[i].symbol, g_scan[i].tf, g_td[i]))
            g_tdBar[i] = g_scan[i].lastBarTime;
        }
     }

   //--- 一目均衡表(確定足が更新された行だけ計算する) ---
   if(ICH_Enable)
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready || g_scan[i].lastBarTime == g_ichBar[i]) continue;
         if(ICH_Compute(g_scan[i].symbol, g_scan[i].tf, g_ich[i]))
            g_ichBar[i] = g_scan[i].lastBarTime;
        }
     }

   //--- ウォルフ波動(確定足が更新された行だけ計算する) ---
   if(WLF_Enable)
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready || g_scan[i].lastBarTime == g_wlfBar[i]) continue;
         if(WLF_Compute(g_scan[i].symbol, g_scan[i].tf, g_wlf[i]))
            g_wlfBar[i] = g_scan[i].lastBarTime;
        }

      //--- ポイント5が確定した行の、検証ログと通知 ---
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!WLF_IsConfirmed(g_wlf[i])) continue;

         int ps = PeriodSeconds(g_scan[i].tf);
         datetime closeT = g_scan[i].lastBarTime + ps;
         double px = iClose(g_scan[i].symbol, g_scan[i].tf, 1);
         if(px <= 0.0 || g_wlf[i].atr <= 0.0) continue;

         bool tdAlign = (TDS_Enable && g_td[i].ready && g_td[i].recent && g_td[i].recentDir == -g_wlf[i].dir);
         bool revBar  = (g_wlf[i].pinBar || g_wlf[i].engulf);
         double p5key = (double)g_wlf[i].t5;

         string feat = WLF_Feat(g_wlf[i]) + ";comp_state=" + CCOMP_StateShort(g_scan[i].state)
                     + ";comp_score=" + IntegerToString(g_scan[i].score);
         if(TDS_Enable && g_td[i].ready)
            feat += ";" + TDS_Feat(g_td[i]) + ";td_align=" + (tdAlign ? "1" : "0");
         if(ICH_Enable && g_ich[i].ready)
            feat += ";" + ICH_Feat(g_ich[i]);

         if(SLG_IsOn())
           {
            if(SAL_FireOnce(GVKey(i, "LW"), p5key))
               SLG_LogEvent("WOLFE5", g_scan[i].symbol, g_scan[i].tf, closeT, px, g_wlf[i].atr, feat);
            if(tdAlign && SAL_FireOnce(GVKey(i, "LWT"), p5key))
               SLG_LogEvent("WOLFE5+TD", g_scan[i].symbol, g_scan[i].tf, closeT, px, g_wlf[i].atr, feat);
            if(tdAlign && revBar && SAL_FireOnce(GVKey(i, "LWP"), p5key))
               SLG_LogEvent("WOLFE5+TD+PIN", g_scan[i].symbol, g_scan[i].tf, closeT, px, g_wlf[i].atr, feat);
           }

         string head = StringFormat("%s %s %s P5確定 EPA%s ETA%d本後 RR%.1f",
                                    g_scan[i].symbol, TFName(g_scan[i].tf), g_wlf[i].dir > 0 ? "買い" : "売り",
                                    DoubleToString(g_wlf[i].epa, g_wlf[i].digits), g_wlf[i].etaBars, g_wlf[i].rr);
         if(WLF_AlertOnWolfe && SAL_FireOnce(GVKey(i, "AW"), p5key))
            SAL_Queue("【ウォルフ波動】" + head);
         if(WLF_AlertOnCombo && tdAlign)
           {
            bool f3 = (revBar && SAL_FireOnce(GVKey(i, "AWP"), p5key));
            bool f2 = SAL_FireOnce(GVKey(i, "AWT"), p5key);
            if(f3)
               SAL_Queue("【ウォルフ+TD+反転足(3条件)】" + head);
            else if(f2 && !revBar)
               SAL_Queue("【ウォルフ+TD】" + head);
           }
        }
     }

   //--- 予兆スコア計算用の配列を作る ---
   {
      int totalImm = g_symbolCount * g_tfCount;
      ArrayResize(g_immScore, totalImm);
      ArrayResize(g_immAct,   totalImm);
      ArrayResize(g_immUp,    totalImm);
      for(int ti = 0; ti < g_tfCount; ti++)
         for(int si = 0; si < g_symbolCount; si++)
           {
            int idx = si * g_tfCount + ti;
            int k   = ti * g_symbolCount + si;
            g_immScore[k] = g_scan[idx].ready ? g_scan[idx].score : 0;
            g_immAct[k]   = (nowT < g_spikeUntil[idx]);
            g_immUp[k]    = g_spikeUp[idx];
           }
   }

   //--- 基準(対照)の記録 ---
   if(SLG_IsOn())
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready || g_scan[i].lastBarTime == g_baseBar[i]) continue;
         g_baseBar[i] = g_scan[i].lastBarTime;

         int tfSecB = PeriodSeconds(g_scan[i].tf);
         bool compB = (g_scan[i].state == CCOMP_COMPRESSION || g_scan[i].state == CCOMP_STRONG_COMPRESSION
                       || g_scan[i].state == CCOMP_TIGHT_COMPRESSION);
         bool takeA = SLG_Sample(g_scan[i].symbol, tfSecB, g_scan[i].lastBarTime, SLG_BaseRate, 1);
         bool takeB = compB && SLG_Sample(g_scan[i].symbol, tfSecB, g_scan[i].lastBarTime, SLG_BaseCompRate, 2);

         bool prevStrong = (g_scan[i].prevBarState == CCOMP_STRONG_COMPRESSION
                            || g_scan[i].prevBarState == CCOMP_TIGHT_COMPRESSION);
         bool scoreFell  = (g_scan[i].prevBarScore >= 0 && g_scan[i].score < g_scan[i].prevBarScore);
         bool riseB = (prevStrong && (g_scan[i].atrRising || g_scan[i].bbRising)
                       && !scoreFell && g_scan[i].state != CCOMP_TRANSITION);
         bool takeC = riseB && SLG_Sample(g_scan[i].symbol, tfSecB, g_scan[i].lastBarTime, SLG_BaseRiseRate, 3);

         if(!takeA && !takeB && !takeC) continue;

         double pxB = iClose(g_scan[i].symbol, g_scan[i].tf, 1);
         if(pxB <= 0.0) continue;
         double atrB = g_scan[i].atrPct / 100.0 * pxB;
         datetime closeB = g_scan[i].lastBarTime + tfSecB;
         string featB = StringFormat("score=%d;state=%s;delta=%d;age=%d;atr_p=%.0f;bb_p=%.0f;rng_p=%.0f;adx=%.1f;kc=%d;nr=%d",
                                     g_scan[i].score, CCOMP_StateShort(g_scan[i].state), g_scan[i].delta, g_scan[i].age,
                                     g_scan[i].atrPctile, g_scan[i].bbPctile, g_scan[i].rangePctile,
                                     g_scan[i].adxValue, g_scan[i].kcSqueeze ? 1 : 0, g_scan[i].isNR ? 1 : 0);
         if(takeA)
            SLG_LogEvent("BASE", g_scan[i].symbol, g_scan[i].tf, closeB, pxB, atrB, featB);
         if(takeB)
            SLG_LogEvent("BASE_COMP", g_scan[i].symbol, g_scan[i].tf, closeB, pxB, atrB, featB);
         if(takeC)
            SLG_LogEvent("BASE_RISE", g_scan[i].symbol, g_scan[i].tf, closeB, pxB, atrB, featB);
        }
     }

   //--- TRANSITION(圧縮解除)の検証ログとアラート ---
   for(int i = 0; i < g_scanTotal; i++)
     {
      if(!g_scan[i].ready || g_scan[i].state != CCOMP_TRANSITION) continue;

      int ps = PeriodSeconds(g_scan[i].tf);
      datetime closeT = g_scan[i].lastBarTime + ps;
      double px = iClose(g_scan[i].symbol, g_scan[i].tf, 1);
      if(px <= 0.0) continue;
      double atrAbs = g_scan[i].atrPct / 100.0 * px;

      REL_Result rrT;
      EVT_Info   evT;
      ComputeRowImminence(i, rrT, evT);

      string feat = StringFormat("score=%d;delta=%d;age=%d;atr_p=%.0f;bb_p=%.0f;rng_p=%.0f;adx=%.1f;kc=%d;nr=%d;imm=%.0f;rel_comp=%.2f;rel_spike=%.2f;ev=%.2f;ev_min=%d;n_rel=%d",
                                 g_scan[i].score, g_scan[i].delta, g_scan[i].age,
                                 g_scan[i].atrPctile, g_scan[i].bbPctile, g_scan[i].rangePctile,
                                 g_scan[i].adxValue, g_scan[i].kcSqueeze ? 1 : 0, g_scan[i].isNR ? 1 : 0,
                                 rrT.pct, rrT.compRel, rrT.spikeRel, rrT.event, evT.minToNext, rrT.nRelated);
      bool tdCombo = (TDS_Enable && g_td[i].ready && g_td[i].recent);
      if(TDS_Enable && g_td[i].ready)
         feat += ";" + TDS_Feat(g_td[i]);

      bool ichCombo = (ICH_Enable && ICH_HasRelease(g_ich[i]));
      if(ICH_Enable && g_ich[i].ready)
         feat += ";" + ICH_Feat(g_ich[i]);

      SLG_LogEvent("TRANSITION", g_scan[i].symbol, g_scan[i].tf, closeT, px, atrAbs, feat);
      if(ichCombo)
         SLG_LogEvent("TRANSITION+ICHI", g_scan[i].symbol, g_scan[i].tf, closeT, px, atrAbs,
                      feat + ";sig=" + (g_ich[i].relDir > 0 ? "up" : "down"));
      if(tdCombo)
         SLG_LogEvent("TRANSITION+TD", g_scan[i].symbol, g_scan[i].tf, closeT, px, atrAbs, feat);

      if(SAL_OnTransition && nowT <= closeT + 2 * ps &&
         SAL_FireOnce(GVKey(i, "AT"), (double)g_scan[i].lastBarTime))
        {
         SAL_Queue(StringFormat("【圧縮解除】%s %s TRANSITION Score%d(Δ%+d) KC%s NR%s",
                                g_scan[i].symbol, TFName(g_scan[i].tf), g_scan[i].score, g_scan[i].delta,
                                g_scan[i].kcSqueeze ? "○" : "×", g_scan[i].isNR ? "○" : "×"));
        }
      if(tdCombo && TDS_AlertOnCombo && SAL_OnTransition && nowT <= closeT + 2 * ps &&
         SAL_FireOnce(GVKey(i, "ATD"), (double)g_scan[i].lastBarTime))
        {
         SAL_Queue(StringFormat("【圧縮解除+TD】%s %s %s%d完了(%d本前) Score%d",
                                g_scan[i].symbol, TFName(g_scan[i].tf),
                                TDS_DirChar(g_td[i].recentDir), g_td[i].recentKind, g_td[i].recentAgo,
                                g_scan[i].score));
        }
      if(ichCombo && ICH_AlertOnCombo && SAL_OnTransition && nowT <= closeT + 2 * ps &&
         SAL_FireOnce(GVKey(i, "ATI"), (double)g_scan[i].lastBarTime))
        {
         SAL_Queue(StringFormat("【圧縮解除+一目 %s】%s %s Score%d",
                                ICH_RelText(g_ich[i]), g_scan[i].symbol, TFName(g_scan[i].tf), g_scan[i].score));
        }
     }

   //--- 急変検知(圧縮中の行が対象。SpikeShowAlways=trueなら全行) ---
   if(UseSpikeOverride)
     {
      for(int i = 0; i < g_scanTotal; i++)
        {
         if(!g_scan[i].ready) continue;

         if(g_suppressed[i] && g_scan[i].state == CCOMP_NORMAL)
           {
            g_suppressed[i] = false;
            SaveSuppressed(i, false);
           }

         if(g_scan[i].state == CCOMP_NORMAL && !SpikeShowAlways) continue;

         SMD_SpikeInfo sp;
         if(!SMD_CheckSpikeV2(g_scan[i].symbol, g_scan[i].tf, g_scan[i].atrHandle, sp))
            continue;

         if(SLG_IsOn() && (sp.v1Spike || sp.isSpike) && sp.atrAvg > 0.0)
           {
            double pxV = SymbolInfoDouble(g_scan[i].symbol, SYMBOL_BID);
            if(pxV > 0.0)
              {
               string featV = StringFormat("dir=%s;atr_ratio=%.2f;atr_ratio_v1=%.2f;z_v1=%.2f;z_robust=%.2f;eff=%.2f;v1=%d;v2=%d;state=%s;score=%d",
                                           sp.isUp ? "up" : "down", sp.atrRatio, sp.atrRatioV1, sp.rocZ, sp.robustZ, sp.efficiency,
                                           sp.v1Spike ? 1 : 0, sp.isSpike ? 1 : 0,
                                           CCOMP_StateShort(g_scan[i].state), g_scan[i].score);
               if(sp.v1Spike && EpisodeFire(i, "SV1", nowT))
                  SLG_LogEvent("SPIKE_V1", g_scan[i].symbol, g_scan[i].tf, nowT, pxV, sp.atrAvg, featV);
               if(sp.isSpike && EpisodeFire(i, "SV2", nowT))
                  SLG_LogEvent("SPIKE_V2", g_scan[i].symbol, g_scan[i].tf, nowT, pxV, sp.atrAvg, featV);
              }
           }

         bool   isSp  = UseSpikeV2 ? sp.isSpike : sp.v1Spike;
         bool   isUp  = sp.isUp;
         double ratio = UseSpikeV2 ? sp.atrRatio : sp.atrRatioV1;
         double z     = UseSpikeV2 ? sp.robustZ  : sp.rocZ;

         if(isSp)
           {
            bool newEpisode = !(nowT < g_spikeUntil[i]);

            g_spikeUntil[i] = nowT + SpikeHoldBars * PeriodSeconds(g_scan[i].tf);
            g_spikeUp[i]    = isUp;
            g_spikeRatio[i] = ratio;
            g_spikeZ[i]     = z;
            SaveSpikeState(i);
            if(g_scan[i].state != CCOMP_NORMAL)
              {
               g_suppressed[i] = true;
               SaveSuppressed(i, true);
              }

            if(newEpisode)
              {
               if(SAL_OnSpike)
                  SAL_Queue(StringFormat("【急変】%s %s %s ATR比%.1f Z%+.1f 効率%.2f",
                                         g_scan[i].symbol, TFName(g_scan[i].tf), isUp ? "上昇" : "下落",
                                         ratio, z, sp.efficiency));

               double px = SymbolInfoDouble(g_scan[i].symbol, SYMBOL_BID);

               REL_Result rrS;
               EVT_Info   evS;
               ComputeRowImminence(i, rrS, evS);

               string feat = StringFormat("dir=%s;ver=%s;atr_ratio=%.2f;atr_ratio_v1=%.2f;z_v1=%.2f;z_robust=%.2f;eff=%.2f;v1=%d;v2=%d;prev_state=%s;score=%d;kc=%d;nr=%d;imm=%.0f;rel_comp=%.2f;rel_spike=%.2f;ev=%.2f;ev_min=%d;n_rel=%d",
                                          isUp ? "up" : "down", UseSpikeV2 ? "V2" : "V1",
                                          sp.atrRatio, sp.atrRatioV1, sp.rocZ, sp.robustZ, sp.efficiency,
                                          sp.v1Spike ? 1 : 0, sp.isSpike ? 1 : 0,
                                          CCOMP_StateShort(g_scan[i].state), g_scan[i].score,
                                          g_scan[i].kcSqueeze ? 1 : 0, g_scan[i].isNR ? 1 : 0,
                                          rrS.pct, rrS.compRel, rrS.spikeRel, rrS.event, evS.minToNext, rrS.nRelated);
               bool tdAlign = (TDS_Enable && TDS_IsReversalAligned(g_td[i], isUp));
               if(TDS_Enable && g_td[i].ready)
                  feat += ";" + TDS_Feat(g_td[i]) + ";td_align=" + (tdAlign ? "1" : "0");

               if(ICH_Enable && g_ich[i].ready)
                  feat += ";" + ICH_Feat(g_ich[i]);

               SLG_LogEvent("SPIKE", g_scan[i].symbol, g_scan[i].tf, nowT, px, sp.atrAvg, feat);
               if(tdAlign)
                 {
                  SLG_LogEvent("SPIKE+TDREV", g_scan[i].symbol, g_scan[i].tf, nowT, px, sp.atrAvg, feat);
                  if(TDS_AlertOnCombo && SAL_OnSpike)
                     SAL_Queue(StringFormat("【急変+TD反転整合】%s %s %s %s%d完了(%d本前)",
                                            g_scan[i].symbol, TFName(g_scan[i].tf), isUp ? "上昇" : "下落",
                                            TDS_DirChar(g_td[i].recentDir), g_td[i].recentKind, g_td[i].recentAgo));
                 }
              }
           }
        }
     }

   // =========================================================================
   // 【WICK検知】 ※ g_scanTotal のループとは独立して実行
   // =========================================================================
   if(UseWickDetector)
     {
      for(int si = 0; si < g_symbolCount; si++)
        {
         for(int ti = 0; ti < g_wickTfCount; ti++)
           {
            string sym = g_symbols[si];
            ENUM_TIMEFRAMES tf = g_wickTfList[ti];
            
            WICK_Info wick;
            if(!WICK_Check(sym, tf, 1, WickRangeMult, WickMinRatio, wick)) continue;
            
            datetime barTime = iTime(sym, tf, 1);
            
            bool duplicate = false;
            for(int h = 0; h < g_wickHistoryCount; h++)
              {
               if(g_wickHistory[h].symbol == sym && 
                  g_wickHistory[h].tf == tf && 
                  g_wickHistory[h].barTime == barTime)
                 {
                  duplicate = true;
                  break;
                 }
              }
            if(duplicate) continue;
            
            if(g_wickHistoryCount >= WickMaxHistory)
              {
               for(int h = WickMaxHistory - 1; h > 0; h--)
                  g_wickHistory[h] = g_wickHistory[h - 1];
              }
            else
              {
               for(int h = g_wickHistoryCount; h > 0; h--)
                  g_wickHistory[h] = g_wickHistory[h - 1];
               g_wickHistoryCount++;
              }
            
            g_wickHistory[0].symbol    = sym;
            g_wickHistory[0].tf        = tf;
            g_wickHistory[0].barTime   = barTime;
            g_wickHistory[0].isUpper   = wick.isUpper;
            g_wickHistory[0].wickRatio = wick.wickRatio;
            g_wickHistory[0].multiplier = wick.multiplier;
            
            if(SLG_IsOn())
              {
               double px = iClose(sym, tf, 1);
               SLG_LogEvent("WICK", sym, tf, barTime, px, wick.totalRange, WICK_Feat(wick));
              }
            
            if(WickAlertOn)
              {
               SAL_Queue(StringFormat("【髭検知】%s %s %s髭 割合%.0f%% 倍率%.1f",
                                      sym, TFName(tf),
                                      wick.isUpper ? "上" : "下",
                                      wick.wickRatio * 100, wick.multiplier));
              }
           }
        }
     }

   // =========================================================================
   // 【フィルタして対象indexと優先度キーを収集】
   // =========================================================================
   int    candIdx[];
   double candKey[];
   int    candKind[];
   ArrayResize(candIdx, g_scanTotal);
   ArrayResize(candKey, g_scanTotal);
   ArrayResize(candKind, g_scanTotal);
   int n = 0;
   int nSpike = 0;
   int nWolfe = 0;
   
   for(int i = 0; i < g_scanTotal; i++)
     {
      if(!g_scan[i].ready) continue;

      if(UseSpikeOverride && nowT < g_spikeUntil[i])
        {
         candIdx[n]  = i;
         candKind[n] = 1;
         candKey[n]  = 200.0 + MathMin(g_spikeRatio[i], 50.0);
         n++;
         nSpike++;
         continue;
        }

      if(UseSpikeOverride && g_suppressed[i]) continue;

      if(!ShouldDisplay(g_scan[i].state))
        {
         if(WLF_Enable && WLF_ListRows && WLF_IsConfirmed(g_wlf[i]))
           {
            double wk = 4.0;
            if(TDS_Enable && g_td[i].ready && g_td[i].recent && g_td[i].recentDir == -g_wlf[i].dir) wk += 0.6;
            if(g_wlf[i].pinBar || g_wlf[i].engulf) wk += 0.3;
            candIdx[n]  = i;
            candKind[n] = 2;
            candKey[n]  = wk;
            n++;
            nWolfe++;
           }
         continue;
        }
      candIdx[n]  = i;
      candKind[n] = 0;
      double baseKey = (double)g_scan[i].score;
      if(SortByImminence)
        {
         REL_Result rrK;
         EVT_Info   evK;
         ComputeRowImminence(i, rrK, evK);
         baseKey = rrK.pct / 12.5;
        }
      candKey[n]  = (g_scan[i].state == CCOMP_TRANSITION) ? (100.0 + baseKey) : baseKey;
      n++;
     }

   //--- 優先度キー降順にソート ---
   for(int a = 0; a < n - 1; a++)
     {
      int best = a;
      for(int b = a + 1; b < n; b++)
        {
         if(candKey[b] > candKey[best])
            best = b;
         else if(candKey[b] == candKey[best])
           {
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
   string title = StringFormat("CCompression Scanner  (圧縮%d件 急変%d件 ウォルフ%d件 / 全%d組)", n - nSpike - nWolfe, nSpike, nWolfe, g_scanTotal);
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
   
   //--- 既存行を一旦全削除してから再構築 ---
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
         line = StringFormat("%-9s %-4s %-20s ATR比%.1f Z%+.1f",
            inst.symbol, tfName, g_spikeUp[idx] ? "急変 ↑ (上昇)" : "急変 ↓ (下落)",
            g_spikeRatio[idx], g_spikeZ[idx]);
         rowClr = g_spikeUp[idx] ? SpikeUpColor : SpikeDownColor;

         if(TDS_Enable && TDS_ShowInList && g_td[idx].ready)
           {
            line += TDS_Text(g_td[idx]);
            if(TDS_IsReversalAligned(g_td[idx], g_spikeUp[idx]))
               line += " ★TD反転整合";
           }
         if(WLF_Enable && WLF_ShowInList)
            line += WLF_Text(g_wlf[idx]);
         if(ICH_Enable && ICH_ShowInList)
            line += ICH_Text(g_ich[idx]);
        }
      else if(candKind[r] == 2)
        {
         line = StringFormat("%-9s %-4s %-20s", inst.symbol, tfName, "ウォルフ波動");
         line += WLF_Text(g_wlf[idx]);
         if(TDS_Enable && TDS_ShowInList && g_td[idx].ready)
           {
            line += TDS_Text(g_td[idx]);
            if(g_td[idx].recent && g_td[idx].recentDir == -g_wlf[idx].dir)
               line += " ★TD整合";
           }
         if(ICH_Enable && ICH_ShowInList)
            line += ICH_Text(g_ich[idx]);
         rowClr = (g_wlf[idx].dir > 0) ? WLF_ColorBuy : WLF_ColorSell;
        }
      else
        {
         line = StringFormat("%-9s %-4s %-20s Sc%d Δ%+d Age%d",
            inst.symbol, tfName, CCOMP_StateText(inst.state), inst.score, inst.delta, inst.age);
         rowClr = CCOMP_StateColor(inst.state);

         if(ShowImminenceInList || ShowEventInList)
           {
            REL_Result rrL;
            EVT_Info   evL;
            ComputeRowImminence(idx, rrL, evL);
            if(ShowImminenceInList && REL_Enable)
               line += StringFormat("  予兆%3.0f%%%s", rrL.pct, rrL.dir > 0 ? "↑" : (rrL.dir < 0 ? "↓" : ""));
            if(ShowEventInList)
               line += EventShort(evL);
           }

         if(TDS_Enable && TDS_ShowInList && g_td[idx].ready)
           {
            line += TDS_Text(g_td[idx]);
            if(inst.state == CCOMP_TRANSITION && g_td[idx].recent)
               line += " ★TD重複";
           }
         if(WLF_Enable && WLF_ShowInList)
            line += WLF_Text(g_wlf[idx]);
         if(ICH_Enable && ICH_ShowInList)
           {
            line += ICH_Text(g_ich[idx]);
            if(inst.state == CCOMP_TRANSITION && ICH_HasRelease(g_ich[idx]))
               line += " ★一目の解除方向あり";
           }
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

   DrawDetailPanel();
   DrawWolfeChart();
   DrawStatsPanel();
   DrawWickPanel();

   SAL_Flush();
   SLG_EvaluatePending();
   SLG_AutoReport();

   ChartRedraw(0);
  }
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
   // 1. クリックイベントでなければ即終了
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // 2. 画面上のON/OFFボタンの処理
   if(sparam == "CCOMP_Scan_BtnLog")
     {
      g_logOn = !g_logOn;
      GlobalVariableSet("CCOMP_UI_LOG", g_logOn ? 1.0 : 0.0);
      SLG_SetOn(g_logOn);
      DrawStatsPanel();
      ChartRedraw(0);
      return;
     }
   if(sparam == "CCOMP_Scan_BtnStats")
     {
      g_statsOn = !g_statsOn;
      GlobalVariableSet("CCOMP_UI_STATS", g_statsOn ? 1.0 : 0.0);
      DrawStatsPanel();
      ChartRedraw(0);
      return;
     }
   if(sparam == "CCOMP_Scan_BtnReport")
     {
      bool ok = SLG_WriteReport();
      if(ok)
         Alert("検証レポートを出力しました: MQL5\\Files\\" + SLG_ReportPath());
      else
         Alert("検証レポートを出力できませんでした(検証ログが初期化されていない、または書き込めません)");
      return;
     }

   // 3. 髭検知パネルの行クリック処理
   string wickPrefix = "CCOMP_Wick_Row_";
   if(StringFind(sparam, wickPrefix) == 0)
     {
      string idxStr = StringSubstr(sparam, StringLen(wickPrefix));
      int r = (int)StringToInteger(idxStr);
      
      if(r >= 0 && r < g_wickHistoryCount)
        {
         string sym = g_wickHistory[r].symbol;
         ENUM_TIMEFRAMES tf = g_wickHistory[r].tf;
         
         if(OpenInNewChart)
            ChartOpen(sym, tf);
         else
            ChartSetSymbolPeriod(0, sym, tf);
        }
      return; // 処理したので終了
     }

   // 4. 圧縮スキャナーパネルの行クリック処理
   string prefix = "CCOMP_Scan_Row_";
   if(StringFind(sparam, prefix) != 0) return; // ← ここがポイント：対象外なら即終了
   
   string idxStr = StringSubstr(sparam, StringLen(prefix));
   int r = (int)StringToInteger(idxStr);
   
   if(r < 0 || r >= g_rowCount) return; // 範囲外なら終了

   string sym = g_rowSymbol[r];
   ENUM_TIMEFRAMES tf = g_rowTF[r];

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
//| 解説パネル                                                         |
//| チャートに表示中の(通貨ペア, 時間足)について、各指標の状態を       |
//| 日本語で解説する。行クリックで切り替えた直後もこの内容が表示される  |
//+------------------------------------------------------------------+
string GetATRExplanation(const int score)
  {
   if(score >= 2) return("1本の値動き：かなり小さい");
   if(score == 1) return("1本の値動き：やや小さい");
   return("1本の値動き：通常～大きめ");
  }

string GetBBExplanation(const int score)
  {
   if(score >= 2) return("価格の広がり：かなり狭い");
   if(score == 1) return("価格の広がり：やや狭い");
   return("価格の広がり：通常～大きい");
  }

string GetRangeExplanation(const int score)
  {
   if(score >= 2) return("20期間の活動範囲：かなり狭い");
   if(score == 1) return("20期間の活動範囲：やや狭い");
   return("20期間の活動範囲：通常～大きい");
  }

string GetADXExplanation(const int score)
  {
   if(score >= 2) return("トレンド強度：弱い");
   if(score == 1) return("トレンド強度：やや弱い");
   return("トレンド強度：強め");
  }

string GetStateExplanation(const CCOMP_STATE st)
  {
   switch(st)
     {
      case CCOMP_NORMAL:             return("通常の値動きです。圧縮は見られません");
      case CCOMP_COMPRESSION:        return("値動きが縮み始めています（弱い圧縮）");
      case CCOMP_STRONG_COMPRESSION: return("値動きがかなり縮んでいます（強い圧縮）");
      case CCOMP_TIGHT_COMPRESSION:  return("値動きが極めて縮んでいます（非常に強い圧縮）");
      case CCOMP_TRANSITION:         return("強い圧縮から値幅が広がり始めました（方向は不明）");
     }
   return("");
  }

string GetDeltaExplanation(const int delta)
  {
   if(delta > 0) return("前回よりScoreが上がり、圧縮が強まっています");
   if(delta < 0) return("前回よりScoreが下がり、圧縮が弱まっています");
   return("前回からScoreの変化はありません");
  }

int g_detailLineCount = 0;   // 前回描画した解説行数(余った行を消すため)

//--- 解説1行を描画。j=上から何行目か、total=全行数
void SetDetailLine(const int j, const int total, const string text, const color clr)
  {
   string name = "CCOMP_Scan_Detail_" + IntegerToString(j);
   bool lower = (DetailCorner == CORNER_LEFT_LOWER  || DetailCorner == CORNER_RIGHT_LOWER);
   bool right = (DetailCorner == CORNER_RIGHT_UPPER || DetailCorner == CORNER_RIGHT_LOWER);

   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }

   ENUM_ANCHOR_POINT anchor;
   if(lower) anchor = right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER;
   else      anchor = right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER;

   int lineH = 16;
   int y = lower ? DetailY + (total - 1 - j) * lineH : DetailY + j * lineH;

   ObjectSetInteger(0, name, OBJPROP_CORNER, DetailCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, DetailX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void DrawDetailPanel()
  {
   if(!ShowDetailPanel)
     {
      ObjectsDeleteAll(0, "CCOMP_Scan_Detail_");
      g_detailLineCount = 0;
      return;
     }

   string lines[30];
   color  clrs[30];
   int    L = 0;

   ENUM_TIMEFRAMES curTF = (ENUM_TIMEFRAMES)_Period;
   string tfName = EnumToString(curTF);
   StringReplace(tfName, "PERIOD_", "");

   int idx = -1;
   for(int i = 0; i < g_scanTotal; i++)
      if(g_scan[i].symbol == _Symbol && g_scan[i].tf == curTF) { idx = i; break; }

   if(idx < 0)
     {
      lines[L] = StringFormat("【解説】%s %s は監視対象外です（時間足の選択ONを確認してください）", _Symbol, tfName);
      clrs[L]  = clrGray; L++;
     }
   else if(!g_scan[idx].ready)
     {
      lines[L] = StringFormat("【解説】%s %s 計算中...", _Symbol, tfName);
      clrs[L]  = clrGray; L++;
     }
   else
     {
      CCOMP_Instance inst = g_scan[idx];
      color base = clrSilver;

      lines[L] = StringFormat("【解説】%s %s   状態: %s   Score %d/8",
                              inst.symbol, tfName, CCOMP_StateText(inst.state), inst.score);
      clrs[L]  = CCOMP_StateColor(inst.state); L++;

      lines[L] = "  " + GetStateExplanation(inst.state);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  ATR    %d/2  %s  (ATR%% %.3f / 過去%d本中 下位%.0f%%)",
                              inst.atrScore, GetATRExplanation(inst.atrScore),
                              inst.atrPct, inst.lookback, inst.atrPctile);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  BB幅   %d/2  %s  (BB幅%% %.3f / 過去%d本中 下位%.0f%%)",
                              inst.bbScore, GetBBExplanation(inst.bbScore),
                              inst.bbWidthPct, inst.lookback, inst.bbPctile);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  Range  %d/2  %s  (Range%% %.3f / 過去%d本中 下位%.0f%%)",
                              inst.rangeScore, GetRangeExplanation(inst.rangeScore),
                              inst.range20Pct, inst.lookback, inst.rangePctile);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  ADX    %d/2  %s  (ADX %.1f)",
                              inst.adxScore, GetADXExplanation(inst.adxScore), inst.adxValue);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  Delta %+d : %s", inst.delta, GetDeltaExplanation(inst.delta));
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  Age %d : 同じ状態が%d本続いています（%s足の確定足ベース）",
                              inst.age, inst.age, tfName);
      clrs[L]  = base; L++;

      lines[L] = StringFormat("  補助: KC圧縮(BB幅がKeltner内)=%s  NR%d(直近%d本中で最小レンジ)=%s",
                              inst.kcSqueeze ? "はい" : "いいえ", CCOMP_NR_Period, CCOMP_NR_Period,
                              inst.isNR ? "はい" : "いいえ");
      clrs[L]  = base; L++;

      // 予兆スコア・関連ペア・指標/開場
      REL_Result rrD;
      EVT_Info   evD;
      ComputeRowImminence(idx, rrD, evD);

      if(REL_Enable)
        {
         lines[L] = StringFormat("  予兆スコア %.0f%%%s  (自身の圧縮%.0f%% / 関連の圧縮%.0f%% / 関連の急変%.0f%% / 指標・開場%.0f%%)  ※目安であり確率ではありません",
                                 rrD.pct, rrD.dir > 0 ? " 方向目安↑" : (rrD.dir < 0 ? " 方向目安↓" : ""),
                                 rrD.compSelf * 100.0, rrD.compRel * 100.0, rrD.spikeRel * 100.0, rrD.event * 100.0);
         clrs[L]  = clrAqua; L++;

         lines[L] = StringFormat("  関連ペア(|相関|%.1f以上): %d本   急変中: %s   強く圧縮中: %s",
                                 REL_MinCorr, rrD.nRelated,
                                 StringLen(rrD.topSpike) > 0 ? rrD.topSpike : "なし",
                                 StringLen(rrD.topComp)  > 0 ? rrD.topComp  : "なし");
         clrs[L]  = base; L++;
        }

      string evNext = (evD.minToNext >= 0)
         ? StringFormat("%s %s(重要度%d) %d分後", evD.nextCur, evD.nextName, evD.nextImp, evD.minToNext)
         : (EVT_UseCalendar ? (g_evtOk ? "なし" : "カレンダー" + EVT_StatusText()) : "(無効)");
      string evLast = (evD.minSinceLast >= 0)
         ? StringFormat("%s %s %d分前", evD.lastCur, evD.lastName, evD.minSinceLast) : "なし";
      lines[L] = StringFormat("  次の指標: %s   直前の指標: %s", evNext, evLast);
      clrs[L]  = base; L++;

      if(EVT_UseSessions)
        {
         lines[L] = (evD.minToSession >= 0)
            ? StringFormat("  次の市場開場: %s %d分後", evD.sessionName, evD.minToSession)
            : "  次の市場開場: なし";
         clrs[L]  = base; L++;
        }

      // TDシーケンシャル
      if(TDS_Enable && g_td[idx].ready)
        {
         TDS_Result td = g_td[idx];
         string setupTxt = (td.setupCount > 0) ? StringFormat("%s %d/9", TDS_DirChar(td.setupDir), td.setupCount) : "なし";
         string cdTxt    = (td.cdCount > 0)    ? StringFormat("%s %d/13", TDS_DirChar(td.cdDir), td.cdCount) : "なし";
         string done = "";
         if(td.lastSetupAgo >= 0)
            done += StringFormat("%s9%s %d本前", TDS_DirChar(td.lastSetupDir), td.lastPerfect ? "(パーフェクト)" : "", td.lastSetupAgo);
         if(td.lastCdAgo >= 0)
           {
            if(StringLen(done) > 0) done += " / ";
            done += StringFormat("%s13 %d本前", TDS_DirChar(td.lastCdDir), td.lastCdAgo);
           }
         if(StringLen(done) == 0) done = "なし";

         lines[L] = StringFormat("  TD: セットアップ進行 %s / カウントダウン進行 %s / 直近の完了: %s", setupTxt, cdTxt, done);
         clrs[L]  = base; L++;

         if(inst.state == CCOMP_TRANSITION && td.recent)
           {
            lines[L] = StringFormat("  判定: 圧縮解除 + 直近にTD完了(%s%d, %d本前)  → 圧縮解除がトレンド疲弊の直後に起きています",
                                    TDS_DirChar(td.recentDir), td.recentKind, td.recentAgo);
            clrs[L]  = clrAqua; L++;
           }

         lines[L] = "  TD凡例: S=上昇が続いた疲弊(売り側) B=下落が続いた疲弊(買い側)。圧縮・急変を置き換えるものではなく補助的な確認用";
         clrs[L]  = clrGray; L++;
        }

      // ウォルフ波動
      if(WLF_Enable && g_wlf[idx].ready)
        {
         WLF_Result w = g_wlf[idx];
         if(!w.found)
           {
            lines[L] = "  ウォルフ波動: 該当なし(直近でポイント5まで揃ったパターンはありません)";
            clrs[L]  = clrGray; L++;
           }
         else
           {
            bool tdAl = (TDS_Enable && g_td[idx].ready && g_td[idx].recent && g_td[idx].recentDir == -w.dir);
            bool rev  = (w.pinBar || w.engulf);
            string revTxt = w.pinBar ? "ピンバー" : (w.engulf ? "包み足" : "なし");

            lines[L] = StringFormat("  ウォルフ波動: %s %s   P1=%s P2=%s P3=%s P4=%s P5=%s",
                                    w.dir > 0 ? "強気(買い)" : "弱気(売り)", w.state == 2 ? "ポイント5確定" : "ポイント5候補",
                                    DoubleToString(w.p1, w.digits), DoubleToString(w.p2, w.digits),
                                    DoubleToString(w.p3, w.digits), DoubleToString(w.p4, w.digits),
                                    DoubleToString(w.p5, w.digits));
            clrs[L]  = (w.dir > 0) ? WLF_ColorBuy : WLF_ColorSell; L++;

            lines[L] = StringFormat("  目標EPA %s  ETA %s  値幅%.1fATR / リスク%.1fATR (RR %.1f)  行き過ぎ%.1fATR  反転足: %s",
                                    DoubleToString(w.epa, w.digits),
                                    (w.etaBars > 0) ? StringFormat("%d本後", w.etaBars) : "経過",
                                    w.rewardATR, w.riskATR, w.rr, w.overshootATR, revTxt);
            clrs[L]  = base; L++;

            string judge;
            if(w.state != 2)
               judge = "ポイント5候補です。終値が1-3ラインの内側へ戻って足が確定するのを待ちます";
            else if(tdAl && rev)
               judge = "ウォルフP5確定 + TD完了 + 反転足 → 3条件が揃っています";
            else if(tdAl)
               judge = "ウォルフP5確定 + TD完了(反転足はまだ)";
            else
               judge = "ウォルフP5確定のみ(TD完了は重なっていません)";
            lines[L] = "  判定: " + judge;
            clrs[L]  = (w.state == 2 && tdAl) ? clrAqua : base; L++;
           }
        }

      // 一目均衡表
      if(ICH_Enable && g_ich[idx].ready)
        {
         ICH_Result ic = g_ich[idx];
         string posTxt = (ic.pos > 0) ? "雲の上" : ((ic.pos < 0) ? "雲の下" : "雲の中");
         lines[L] = StringFormat("  一目均衡表: 価格は%s  雲の厚み%.2f%%(過去%d本中 下位%.0f%%)%s  基準線%s  転換線-基準線 %.1fATR  一目の圧縮度 %d/4",
                                 posTxt, ic.thickPct, ICH_PctBars, ic.thickPctile, ic.thin ? "=薄い" : "",
                                 ic.kijunFlat ? "は横ばい" : "は傾き有り", ic.tkDistATR, ic.score);
         clrs[L]  = base; L++;

         lines[L] = StringFormat("  三役: 好転%d/3 逆転%d/3  遅行スパン:%s  先行スパンのねじれ(26本先まで):%s",
                                 ic.bullRoles, ic.bearRoles,
                                 ic.chikou > 0 ? "26本前の価格より上" : (ic.chikou < 0 ? "26本前の価格より下" : "同じ"),
                                 ic.twistAhead ? "あり" : "なし");
         clrs[L]  = base; L++;

         if(ic.relKind != 0)
           {
            lines[L] = StringFormat("  解除の方向: %s(%d本前)  ※三役が%d以上その方向に揃っているものだけを数えています",
                                    ICH_RelText(ic), ic.relAgo, ICH_MinRoles);
            clrs[L]  = (ic.relDir > 0) ? WLF_ColorBuy : WLF_ColorSell; L++;
           }

         if(inst.state == CCOMP_TRANSITION && ic.relKind != 0)
           {
            lines[L] = "  判定: 圧縮解除(TRANSITION) + 一目の解除方向 → 解除の方向の裏づけがあります";
            clrs[L]  = clrAqua; L++;
           }
         else if(inst.state != CCOMP_NORMAL && ic.thin && ic.pos == 0)
           {
            lines[L] = "  判定: 一目均衡表も圧縮を示しています(薄い雲の中に価格がある)";
            clrs[L]  = base; L++;
           }
        }

      // 急変との連携状況
      if(UseSpikeOverride && TimeCurrent() < g_spikeUntil[idx])
        {
         lines[L] = StringFormat("  急変検知中: %s  ATR比%.1f Z%+.1f  （一覧では圧縮表示を解除し急変として表示）",
                                 g_spikeUp[idx] ? "上昇" : "下落", g_spikeRatio[idx], g_spikeZ[idx]);
         clrs[L]  = g_spikeUp[idx] ? SpikeUpColor : SpikeDownColor; L++;
        }
      else if(UseSpikeOverride && g_suppressed[idx])
        {
         lines[L] = "  急変により圧縮表示を解除中（圧縮がNORMALに戻るまで一覧には出ません）";
         clrs[L]  = clrGray; L++;
        }
     }

   for(int j = 0; j < L; j++)
      SetDetailLine(j, L, lines[j], clrs[j]);

   // 前回より行数が減った場合、余った行を消す
   for(int j = L; j < g_detailLineCount; j++)
      ObjectDelete(0, "CCOMP_Scan_Detail_" + IntegerToString(j));
   g_detailLineCount = L;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 検証パネル: 結果記録(SignalLogger)の集計を右上に表示              |
//| 「TRANSITIONや急変のあと、実際にATRの何倍動いたか」を確認する     |
//+------------------------------------------------------------------+
int g_statLineCount = 0;

//--- 右上のON/OFFボタンを1つ描画
void DrawUiButton(const string name, const int x, const string text, const color bg)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 128);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, StatsY);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);   // 押しっぱなし表示にならないよう戻す
  }

void DrawStatsPanel()
  {
   //--- ボタン(検証パネルを隠していても常に表示する) ---
   DrawUiButton("CCOMP_Scan_BtnStats", StatsX,
                g_statsOn ? "検証パネル: 表示" : "検証パネル: 非表示",
                g_statsOn ? C'40,90,40' : C'70,70,70');
   DrawUiButton("CCOMP_Scan_BtnLog", StatsX + 132,
                g_logOn ? "ログ記録: ON" : "ログ記録: OFF",
                g_logOn ? C'40,90,40' : C'110,40,40');
   DrawUiButton("CCOMP_Scan_BtnReport", StatsX + 264, "レポート出力", C'40,70,110');

   if(!g_statsOn)
     {
      ObjectsDeleteAll(0, "CCOMP_Scan_Stat_");
      g_statLineCount = 0;
      return;
     }

   string lines[];
   int n = 0;
   string head;
   if(!SLG_IsReady())
      head = "検証ログ: 無効(SLG_Enableをtrueにしてください)";
   else
     {
      n = SLG_GetStatLines(lines);
      head = StringFormat("検証ログ[%s]: 記録%d件 / 評価済%d行", SLG_IsOn() ? "記録中" : "停止中", SLG_EventCount(), SLG_DoneCount());
     }

   int total = 1 + (n > 0 ? n : 1);
   for(int j = 0; j < total; j++)
     {
      string name = "CCOMP_Scan_Stat_" + IntegerToString(j);
      string text;
      color  clr = clrSilver;
      if(j == 0)       { text = head; clr = clrWhite; }
      else if(n == 0)  { text = "  (評価済みのデータはまだありません)"; clr = clrGray; }
      else             text = "  " + lines[j - 1];

      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
        }
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, StatsX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, StatsY + 28 + j * 15);   // ボタンの下から表示
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
     }

   for(int j = total; j < g_statLineCount; j++)
      ObjectDelete(0, "CCOMP_Scan_Stat_" + IntegerToString(j));
   g_statLineCount = total;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ウォルフ波動のチャート描画                                         |
//| 現在のチャートの通貨ペア・時間足に、パターンがあればラインを描く   |
//+------------------------------------------------------------------+
void DrawWolfeChart()
  {
   if(!WLF_Enable || !WLF_DrawOnChart)
     {
      WLF_ClearDrawing();
      return;
     }
   ENUM_TIMEFRAMES curTF = (ENUM_TIMEFRAMES)_Period;
   int idx = -1;
   for(int i = 0; i < g_scanTotal; i++)
      if(g_scan[i].symbol == _Symbol && g_scan[i].tf == curTF) { idx = i; break; }

   if(idx < 0 || !g_wlf[idx].ready || !g_wlf[idx].found)
     {
      WLF_ClearDrawing();
      return;
     }
   WLF_DrawPattern(g_wlf[idx]);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 髭検知パネル                                                       |
//+------------------------------------------------------------------+
int g_wickLineCount = 0;

void DrawWickPanel()
{
   if(!UseWickDetector)
     {
      ObjectsDeleteAll(0, "CCOMP_Wick_");
      g_wickLineCount = 0;
      return;
     }

   //--- タイトル
   string titleName = "CCOMP_Wick_Title";
   if(ObjectFind(0, titleName) < 0)
     {
      ObjectCreate(0, titleName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, titleName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, titleName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, titleName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, titleName, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
     }
   ObjectSetInteger(0, titleName, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, titleName, OBJPROP_YDISTANCE, 10);
   ObjectSetString(0, titleName, OBJPROP_TEXT, StringFormat("【髭検知】最新%d件 (×%.1f / ≥%.0f%%)", g_wickHistoryCount, WickRangeMult, WickMinRatio * 100));
   ObjectSetInteger(0, titleName, OBJPROP_COLOR, clrYellow);

   //--- 履歴行
   int shown = MathMin(g_wickHistoryCount, 20); // 最大20行
   for(int r = 0; r < shown; r++)
     {
      string name = "CCOMP_Wick_Row_" + IntegerToString(r);
      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
        }
        
      // ▼ 既存オブジェクトの場合でも、毎回プロパティを上書きしてクリック可能を保証する
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 100); // クリック優先度を高くする
      
      WICK_HistoryItem item = g_wickHistory[r];
      string tfName = EnumToString(item.tf);
      StringReplace(tfName, "PERIOD_", "");
      
      string text = StringFormat("%-9s %-4s %s髭 割合%.0f%% 倍率%.1f",
                                 item.symbol, tfName,
                                 item.isUpper ? "上" : "下",
                                 item.wickRatio * 100, item.multiplier);
      
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 30 + r * 14);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, item.isUpper ? clrRed : clrLime);
     }

   //--- 余分行の削除
   for(int r = shown; r < g_wickLineCount; r++)
      ObjectDelete(0, "CCOMP_Wick_Row_" + IntegerToString(r));
   g_wickLineCount = shown;
}
//+------------------------------------------------------------------+
//|                                            SMD_HistoryCheck.mq5   |
//|  急変検知の過去チェック(スクリプト)                                |
//|                                                                    |
//|  「あの時刻の急な値動きを、急変検知は検知できたか?」を、実際の      |
//|  過去データで確かめる。指定した時刻の前後の足を1本ずつ、             |
//|  実運用と同じ判定式(SuddenMoveDetector.mqh の V1・V2)で判定し、     |
//|  結果と、各条件の数値を表にして出す。                              |
//|                                                                    |
//|  【使い方】                                                       |
//|   1) 調べたい通貨ペア・時間足のチャートを開く(またはInpSymbol/InpTF)|
//|   2) ナビゲーターの「スクリプト」から、このスクリプトをチャートへ   |
//|   3) InpTime に調べたい時刻を入れる(既定は日本時間)               |
//|   4) 結果は「エキスパート」タブと、                                |
//|      Files\\Verification log\\SMD_HistoryCheck.txt に出る           |
//|                                                                    |
//|  【注意】                                                         |
//|  ・足の最終的な高値・安値・終値で判定している。実運用は形成中の足を   |
//|    1秒ごとに判定するので、足の途中で先に検知される場合もある。       |
//|  ・日本時間とサーバー時間の変換は、現在のサーバー時間のずれを使う。   |
//|    夏時間をまたぐ古い日付では、1時間ずれることがある。              |
//|  ・判定に使う閾値(SMD_...)は、入力欄に出る。変えて試せる。          |
//+------------------------------------------------------------------+
#property copyright "SMD history check"
#property version   "1.00"
#property script_show_inputs
#property strict

#include "../../Indicators/claude.ai/MarketEngines/SuddenMoveDetector.mqh"

input string          InpSymbol     = "";                 // 銘柄(空欄=チャートの銘柄)
input ENUM_TIMEFRAMES InpTF         = PERIOD_CURRENT;     // 時間足(PERIOD_CURRENT=チャートの時間足)
input string          InpTime       = "2026.10.21 15:00"; // 調べたい時刻(例 2026.10.21 15:00)
input bool            InpIsJST      = true;               // true=日本時間 / false=サーバー時間
input int             InpBarsBefore = 5;                  // 指定した足より前に表示する本数
input int             InpBarsAfter  = 20;                 // 指定した足より後に表示する本数
input bool            InpWriteFile  = true;               // 結果を Files\Verification log\SMD_HistoryCheck.txt にも出力する

void AddLine(string &arr[], const string s)
  {
   int k = ArraySize(arr);
   ArrayResize(arr, k + 1, 64);
   arr[k] = s;
  }

//+------------------------------------------------------------------+
void OnStart()
  {
   string sym = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   ENUM_TIMEFRAMES tf = (InpTF == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTF;
   if(!SymbolSelect(sym, true))
     {
      Print("SMD_HistoryCheck: 銘柄を選択できません: ", sym);
      return;
     }

   //--- 時刻の変換(日本時間→サーバー時間) ---
   long off = (long)TimeTradeServer() - (long)TimeGMT();   // サーバー時間とUTCの差
   off = ((off + 450) / 900) * 900;                        // 15分単位に丸める
   datetime t = StringToTime(InpTime);
   datetime serverT = InpIsJST ? (datetime)((long)t - 9 * 3600 + off) : t;

   int center = iBarShift(sym, tf, serverT, false);
   if(center < 0)
     {
      Print("SMD_HistoryCheck: 指定した時刻の足が見つかりません(履歴が足りない可能性があります)");
      return;
     }

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double pip = (digits == 3 || digits == 5) ? point * 10.0 : point;

   int hATR = iATR(sym, tf, SMD_ATR_Period);
   if(hATR == INVALID_HANDLE)
     {
      Print("SMD_HistoryCheck: iATRのハンドルを作成できません");
      return;
     }
   for(int w = 0; w < 50 && BarsCalculated(hATR) <= 0; w++)
      Sleep(100);

   int fromShift = center + MathMax(0, InpBarsBefore);   // 古い側
   int toShift   = MathMax(0, center - MathMax(0, InpBarsAfter));   // 新しい側

   string L[];
   AddLine(L, "=== 急変検知の過去チェック ===");
   AddLine(L, StringFormat("対象: %s %s   調べたい時刻: %s(%s) → サーバー時間 %s   (サーバー時間-UTC=%+d時間)",
                           sym, EnumToString(tf), InpTime, InpIsJST ? "日本時間" : "サーバー時間",
                           TimeToString(serverT, TIME_DATE | TIME_MINUTES), (int)(off / 3600)));
   AddLine(L, StringFormat("判定条件: V1 = ATR比(値幅/ATR)>=%.1f かつ |Z|>=%.1f / V2 = ATR比(ギャップ込み)>=%.1f かつ |ロバストZ|>=%.1f かつ 方向効率>=%.2f (ロールオーバー除外%d分)",
                           SMD_ATR_SpikeMult, SMD_ROC_ZThreshold, SMD_ATR_SpikeMult, SMD_RobustZThreshold,
                           SMD_MinEfficiency, SMD_RolloverExcludeMin));
   AddLine(L, StringFormat("ATR期間=%d / ROC期間=%d本 / Zスコアの過去本数=%d本。ATR比・Z・ロバストZ・方向効率が、V1/V2の判定に使う数値。", SMD_ATR_Period, SMD_ROC_Period, SMD_ROC_ZLookback));
   AddLine(L, "足の時刻(サーバー)  足の時刻(日本)   | 値幅  上髭 下髭 | ATR    ATR比V1 ATR比V2   Z   ロバストZ 方向効率 | 判定");
   AddLine(L, "                                      | pips  %    %    | pips                                          |");

   int v1Count = 0, v2Count = 0;
   datetime v1First = 0, v2First = 0;
   for(int sh = fromShift; sh >= toShift; sh--)
     {
      datetime bt = iTime(sym, tf, sh);
      double o = iOpen(sym, tf, sh);
      double h = iHigh(sym, tf, sh);
      double l = iLow(sym, tf, sh);
      double c = iClose(sym, tf, sh);
      double rng = h - l;
      double up  = h - MathMax(o, c);
      double lo  = MathMin(o, c) - l;

      string srv = TimeToString(bt, TIME_DATE | TIME_MINUTES);
      string jst = TimeToString((datetime)((long)bt - off + 9 * 3600), TIME_DATE | TIME_MINUTES);
      string mark = (sh == center) ? " ◀指定した足" : "";

      SMD_SpikeInfo sp;
      if(!SMD_CheckSpikeV2At(sym, tf, hATR, sh, sp))
        {
         AddLine(L, StringFormat("%s  %s  | 計算できません(履歴不足など)%s", srv, jst, mark));
         continue;
        }

      if(sp.v1Spike) { v1Count++; if(v1First == 0) v1First = bt; }
      if(sp.isSpike) { v2Count++; if(v2First == 0) v2First = bt; }

      AddLine(L, StringFormat("%s  %s  | %5.1f %3.0f%% %3.0f%% | %5.1f  %6.1f %6.1f  %6.1f %7.1f   %5.2f   | %s %s%s",
                              srv, jst, rng / pip,
                              (rng > 0.0) ? up / rng * 100.0 : 0.0, (rng > 0.0) ? lo / rng * 100.0 : 0.0,
                              sp.atrAvg / pip, sp.atrRatioV1, sp.atrRatio, sp.rocZ, sp.robustZ, sp.efficiency,
                              sp.v1Spike ? "V1" : "--", sp.isSpike ? "V2" : "--", mark));
     }

   AddLine(L, "");
   AddLine(L, StringFormat("まとめ: 表示した範囲でV1が反応した足=%d本%s / V2が反応した足=%d本%s",
                           v1Count, (v1First > 0) ? "(最初: " + TimeToString(v1First, TIME_DATE | TIME_MINUTES) + ")" : "",
                           v2Count, (v2First > 0) ? "(最初: " + TimeToString(v2First, TIME_DATE | TIME_MINUTES) + ")" : ""));
   AddLine(L, "読み方: ATR比が高いのに、Z・ロバストZ・方向効率が低い足は、髭(行って戻った値動き)の可能性が高い。");
   AddLine(L, "        髭の足は、値幅(ATR比)は大きいが、終値が動いていないので、終値ベースのZや方向効率には出にくい。");
   AddLine(L, "        髭のあとの足のATR比が低いのは、髭の足がATRを押し上げているため(その後の14本ほど、基準が大きくなる)。");

   for(int i = 0; i < ArraySize(L); i++)
      Print(L[i]);

   if(InpWriteFile)
     {
      FolderCreate("Verification log");
      string path = "Verification log\\SMD_HistoryCheck.txt";
      int fh = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_UNICODE);
      if(fh == INVALID_HANDLE)
         PrintFormat("SMD_HistoryCheck: ファイルに書き込めません %s (error=%d)", path, GetLastError());
      else
        {
         for(int i = 0; i < ArraySize(L); i++)
            FileWriteString(fh, L[i] + "\r\n");
         FileClose(fh);
         PrintFormat("SMD_HistoryCheck: 結果を出力しました MQL5\\Files\\%s", path);
        }
     }

   IndicatorRelease(hATR);
  }
//+------------------------------------------------------------------+

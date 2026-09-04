//+------------------------------------------------------------------+
//|                                          SMD_BacktestEA.mq5       |
//|  急変検知モジュールの過去検証用EA                                 |
//|                                                                    |
//|  【使い方】                                                        |
//|  1) このファイルとSuddenMoveDetector.mqhを同じフォルダ            |
//|     (MQL5/Experts)に置いてコンパイル                              |
//|  2) MT5のストラテジーテスターを開く(Ctrl+R)                       |
//|  3) エキスパート: SMD_BacktestEA を選択                           |
//|  4) 通貨ペア: NZDJPY(何でもOK。実際の判定は内部で複数ペア監視)   |
//|  5) 期間: 2026.08.25 〜 2026.09.05 のように急変前後を含める       |
//|  6) モデル: 「すべてのティック」推奨                              |
//|  7) 「ビジュアルモード」にチェックを入れて開始                    |
//|  8) 再生すると、急変検知時にチャート上にコメントとアラートが出る  |
//|     ので、9/2周辺で実際に検知されるか確認できる                   |
//|                                                                    |
//|  ※このEAは発注は一切行わない。検知ロジックの確認専用。            |
//+------------------------------------------------------------------+
#property copyright "backtest utility"
#property version   "1.00"
#property strict

#include "SuddenMoveDetector.mqh"

input ENUM_TIMEFRAMES TestTimeframe        = PERIOD_M5;
input int             PivotLookbackDays    = 20;      // Pivot幅の平均算出に使う日数
input double          PivotSqueezeThresh   = 0.6;     // これ未満で「狭い」と判定(平均比)
input int             AlertCooldownSec     = 3600;    // 同一シンボルの連続アラート抑制(秒)

string g_symbols[] = {"NZDJPY","AUDJPY","GBPJPY","EURJPY","CADJPY","CHFJPY"};

//+------------------------------------------------------------------+
int OnInit()
  {
   SMD_Init(g_symbols, ArraySize(g_symbols), TestTimeframe);
   Print("SMD_BacktestEA 初期化完了。監視ペア数=", ArraySize(g_symbols));
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

//+------------------------------------------------------------------+
//| 新しいバー確定ごとにチェック(過度な呼び出しを避けるため)          |
//+------------------------------------------------------------------+
datetime g_lastBarTime = 0;

void OnTick()
  {
   datetime curBarTime = iTime(_Symbol, TestTimeframe, 0);
   if(curBarTime == g_lastBarTime)
      return;
   g_lastBarTime = curBarTime;

   SMD_Update();

   string report = StringFormat("[%s] --- 急変検知チェック ---", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

   //--- 個別ペアのスパイク状況を表示
   for(int i = 0; i < ArraySize(g_symbols); i++)
     {
      SMD_SymbolState st;
      if(!SMD_GetState(i, st)) continue;

      if(st.isSpike)
        {
         string dir = st.isDirUp ? "上昇" : "下落";
         report += StringFormat("\n[SPIKE] %s %s ATR比=%.2f ROC_Z=%.2f",
                                 st.symbol, dir, st.atrRatio, st.rocZScore);

         if(SMD_ShouldFireAlert(g_SMD_States[i], AlertCooldownSec))
            Alert(StringFormat("急変検知: %s %s (ATR比%.2f / Z=%.2f)", st.symbol, dir, st.atrRatio, st.rocZScore));
        }
     }

   //--- 複数ペア同時性チェック(広範なリスクオフ/オン)
   bool isRiskOff;
   if(SMD_IsBroadRiskMove(isRiskOff))
     {
      string msg = isRiskOff ? "★広範なリスクオフ検知(JPYクロス全面安)" : "★広範なリスクオン検知(JPYクロス全面高)";
      report += "\n" + msg;
      Alert(msg);
     }

   //--- Pivotスクイーズ(前日の警戒サイン)チェック
   int squeezeCount = SMD_CountPivotSqueezeSymbols(PivotLookbackDays, PivotSqueezeThresh);
   report += StringFormat("\nPivotスクイーズ中のペア数: %d / %d", squeezeCount, ArraySize(g_symbols));
   if(squeezeCount >= SMD_MinAlignedPairs)
      report += "\n⚠ 市場全体が方向感を欠いて溜め込み中 = 急変前兆の可能性";

   Comment(report);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   // タイマーは主にライブ運用時の定期更新用。バックテストではOnTickで十分。
  }
//+------------------------------------------------------------------+

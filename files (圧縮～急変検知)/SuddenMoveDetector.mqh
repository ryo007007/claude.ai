//+------------------------------------------------------------------+
//|                                        SuddenMoveDetector.mqh     |
//|  急変検知モジュール - MTF_TrendSignダッシュボードへの組込み用       |
//|                                                                    |
//|  ATRスパイク + ROC(Zスコア) + 複数JPYクロス同時性チェックにより、  |
//|  NZDJPY等の先行的な急落・急騰を検知し、リスクオフ/リスクオンの     |
//|  早期シグナルとしてアラートを出す。                                |
//|                                                                    |
//|  使い方:                                                          |
//|    1) MTF_TrendSignのメインファイル冒頭に                        |
//|       #include "SuddenMoveDetector.mqh"                           |
//|    2) OnInit() 内で SMD_Init(symbols, symbolCount, tf);           |
//|    3) OnTimer() 内(既存の更新ループの中)で                        |
//|       SMD_Update(); を呼ぶ                                        |
//|    4) SMD_GetAlertCount() が閾値以上ならリスクオフ/オン判定して    |
//|       既存のアラート関数(Push/Popup/Sound)を呼び出す              |
//+------------------------------------------------------------------+
#property strict

//--- パラメータ(必要に応じてメインファイル側でoverride可能)
input group "=== 急変検知モジュール設定 ==="
input int      SMD_ATR_Period        = 14;     // ATR計算期間
input double   SMD_ATR_SpikeMult     = 2.5;    // ATRスパイク判定倍率(直近バーレンジ/平均ATR)
input int      SMD_ROC_Period        = 5;      // ROC計算期間(本数)
input int      SMD_ROC_ZLookback     = 50;     // ROC平均・標準偏差算出用の過去本数
input double   SMD_ROC_ZThreshold    = 2.0;    // ROC Zスコア閾値(標準偏差の何倍で急変とみなすか)
input int      SMD_MinAlignedPairs   = 3;      // 何ペア同時検知でリスクオフ/オン確定とみなすか
input bool     SMD_OnlyJPYCrosses    = true;   // JPYクロスのみを対象にするか

//--- 内部構造体: 監視ペアごとの状態
struct SMD_SymbolState
  {
   string   symbol;
   int      atrHandle;       // iATRハンドル(Init時に1回だけ作成)
   double   atrCurrent;      // 直近バーのレンジ(High-Low)
   double   atrAverage;      // 平均ATR
   double   atrRatio;        // atrCurrent / atrAverage
   double   rocZScore;       // ROCのZスコア
   bool     atrSpike;        // ATR基準の急変フラグ
   bool     rocSpike;        // ROC基準の急変フラグ
   bool     isSpike;         // 最終判定(ATR かつ ROC の両方を満たす場合のみtrue)
   bool     isDirUp;         // 急変の方向(true=上昇, false=下落)
   datetime lastAlertTime;   // 直近アラート時刻(連発防止用)
  };

SMD_SymbolState g_SMD_States[];
ENUM_TIMEFRAMES g_SMD_TF = PERIOD_M5;
int             g_SMD_Count = 0;

//+------------------------------------------------------------------+
//| 初期化: 監視対象シンボル配列と時間足を登録                        |
//+------------------------------------------------------------------+
bool SMD_Init(const string &symbols[], const int count, const ENUM_TIMEFRAMES tf)
  {
   g_SMD_TF = tf;
   g_SMD_Count = count;
   ArrayResize(g_SMD_States, count);
   for(int i = 0; i < count; i++)
     {
      g_SMD_States[i].symbol       = symbols[i];
      g_SMD_States[i].atrCurrent   = 0.0;
      g_SMD_States[i].atrAverage   = 0.0;
      g_SMD_States[i].atrRatio     = 0.0;
      g_SMD_States[i].rocZScore    = 0.0;
      g_SMD_States[i].atrSpike     = false;
      g_SMD_States[i].rocSpike     = false;
      g_SMD_States[i].isSpike      = false;
      g_SMD_States[i].isDirUp      = false;
      g_SMD_States[i].lastAlertTime = 0;

      if(!SymbolSelect(symbols[i], true))
         PrintFormat("SMD_Init: シンボル選択失敗 %s", symbols[i]);

      //--- ハンドルはここで1回だけ作成する(毎ティック作成すると計算が
      //--- 間に合わずATR比が常に0になるバグの原因になるため)
      g_SMD_States[i].atrHandle = iATR(symbols[i], tf, SMD_ATR_Period);
      if(g_SMD_States[i].atrHandle == INVALID_HANDLE)
         PrintFormat("SMD_Init: iATRハンドル作成失敗 %s", symbols[i]);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| 終了処理: 作成したインジケーターハンドルを解放する。               |
//| OnDeinit() から必ず呼び出すこと(呼ばないとハンドルリークする)     |
//+------------------------------------------------------------------+
void SMD_Deinit()
  {
   for(int i = 0; i < g_SMD_Count; i++)
     {
      if(g_SMD_States[i].atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_SMD_States[i].atrHandle);
     }
  }

//+------------------------------------------------------------------+
//| 1シンボル分のATR比率とROC Zスコアを計算                           |
//+------------------------------------------------------------------+
bool SMD_CalcSymbol(SMD_SymbolState &st)
  {
   //--- ATR(直近バーのレンジ vs 平均ATR)。ハンドルはSMD_Initで作成済みのものを使う。
   //--- 毎回作成/破棄すると計算が間に合わずATR比が常に0になるので注意。
   if(st.atrHandle == INVALID_HANDLE)
      return false;

   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(st.atrHandle, 0, 1, 1, atrBuf) <= 0)
      return false;  // まだ計算が済んでいない場合はスキップ(次のティックで再試行)

   st.atrAverage = atrBuf[0];

   double high1 = iHigh(st.symbol, g_SMD_TF, 0);
   double low1  = iLow(st.symbol, g_SMD_TF, 0);
   st.atrCurrent = high1 - low1;

   if(st.atrAverage > 0)
      st.atrRatio = st.atrCurrent / st.atrAverage;
   else
      st.atrRatio = 0.0;

   st.atrSpike = (st.atrRatio >= SMD_ATR_SpikeMult);

   //--- ROCのZスコア(過去SMD_ROC_ZLookback本のROC分布に対して現在のROCが何σか)
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   int needed = SMD_ROC_ZLookback + SMD_ROC_Period + 2;
   if(CopyClose(st.symbol, g_SMD_TF, 0, needed, closeBuf) <= 0)
      return false;

   int n = SMD_ROC_ZLookback;
   double rocArr[];
   ArrayResize(rocArr, n);
   for(int i = 0; i < n; i++)
     {
      double c0 = closeBuf[i];
      double c1 = closeBuf[i + SMD_ROC_Period];
      rocArr[i] = (c1 != 0.0) ? (c0 - c1) / c1 * 100.0 : 0.0;
     }

   double mean = 0.0;
   for(int i = 0; i < n; i++)
      mean += rocArr[i];
   mean /= n;

   double variance = 0.0;
   for(int i = 0; i < n; i++)
      variance += MathPow(rocArr[i] - mean, 2);
   variance /= n;
   double stdev = MathSqrt(variance);

   double currentROC = rocArr[0];
   st.rocZScore = (stdev > 0) ? (currentROC - mean) / stdev : 0.0;
   st.isDirUp = (currentROC > 0);
   st.rocSpike = (MathAbs(st.rocZScore) >= SMD_ROC_ZThreshold);

   //--- 最終判定: ATRとROCの両方を満たす場合のみ「急変」とする(AND条件)。
   //--- どちらか一方だけだと、通常のセッション内値動きでも頻繁にヒットしてしまう。
   st.isSpike = st.atrSpike && st.rocSpike;

   return true;
  }

//+------------------------------------------------------------------+
//| 全監視シンボルを更新。OnTimer等から定期的に呼び出す                |
//+------------------------------------------------------------------+
void SMD_Update()
  {
   for(int i = 0; i < g_SMD_Count; i++)
      SMD_CalcSymbol(g_SMD_States[i]);
  }

//+------------------------------------------------------------------+
//| 現在「急変中」と判定されているシンボル数を返す(方向別)             |
//| dirUp = true なら上昇急変の数、false なら下落急変の数を数える     |
//+------------------------------------------------------------------+
int SMD_GetAlertCount(const bool dirUp)
  {
   int cnt = 0;
   for(int i = 0; i < g_SMD_Count; i++)
     {
      if(g_SMD_States[i].isSpike && g_SMD_States[i].isDirUp == dirUp)
         cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| リスクオフ/オンの「広がり」を確認: 閾値以上のペアが同方向で急変    |
//| していればtrueを返す(単発ノイズと本格的な流れを区別するため)       |
//+------------------------------------------------------------------+
bool SMD_IsBroadRiskMove(bool &isRiskOff)
  {
   int upCount   = SMD_GetAlertCount(true);
   int downCount = SMD_GetAlertCount(false);

   if(downCount >= SMD_MinAlignedPairs)
     {
      isRiskOff = true;   // JPYクロス全面安 = リスクオフ(円買い)
      return true;
     }
   if(upCount >= SMD_MinAlignedPairs)
     {
      isRiskOff = false;  // JPYクロス全面高 = リスクオン(円売り)
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 個別シンボルの状態を取得(パネル表示用)                             |
//+------------------------------------------------------------------+
bool SMD_GetState(const int index, SMD_SymbolState &outState)
  {
   if(index < 0 || index >= g_SMD_Count)
      return false;
   outState = g_SMD_States[index];
   return true;
  }

//+------------------------------------------------------------------+
//| 連発防止付きアラート発火判定。呼び出し側でPush/Popup/Soundを実行   |
//| する前に、このチェックを通すことでスパム通知を防ぐ                 |
//+------------------------------------------------------------------+
bool SMD_ShouldFireAlert(SMD_SymbolState &st, const int cooldownSeconds)
  {
   if(!st.isSpike)
      return false;
   if(TimeCurrent() - st.lastAlertTime < cooldownSeconds)
      return false;
   st.lastAlertTime = TimeCurrent();
   return true;
  }

//+------------------------------------------------------------------+
//| Pivotスクイーズ検知(前日警戒シグナル)                             |
//|                                                                    |
//| 前日レンジから算出したR1-S1幅が、過去N日平均に対してどれだけ       |
//| 狭いかを見る。狭いほど「市場が方向感を欠いて溜め込んでいる」状態  |
//| =急変の前兆である可能性が高い。                                   |
//|                                                                    |
//| squeezeRatio: 1.0未満で「平均より狭い」。0.5なら平均の半分の幅。  |
//| 戻り値: true = スクイーズ状態(閾値以下)                           |
//+------------------------------------------------------------------+
bool SMD_CheckPivotSqueeze(const string symbol, const int lookbackDays,
                            const double squeezeThreshold, double &outRatio)
  {
   double highBuf[], lowBuf[], closeBuf[];
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);
   ArraySetAsSeries(closeBuf, true);

   int needed = lookbackDays + 2;
   if(CopyHigh(symbol, PERIOD_D1, 1, needed, highBuf) <= 0)  return false;
   if(CopyLow(symbol, PERIOD_D1, 1, needed, lowBuf) <= 0)    return false;
   if(CopyClose(symbol, PERIOD_D1, 1, needed, closeBuf) <= 0) return false;

   //--- 直近(前日確定足)のR1-S1幅
   //--- 標準ピボット: Pivot=(H+L+C)/3, R1=2*Pivot-L, S1=2*Pivot-H
   double pivot0 = (highBuf[0] + lowBuf[0] + closeBuf[0]) / 3.0;
   double r1_0   = 2.0 * pivot0 - lowBuf[0];
   double s1_0   = 2.0 * pivot0 - highBuf[0];
   double range0 = r1_0 - s1_0;

   //--- 過去lookbackDays日平均のR1-S1幅
   double sumRange = 0.0;
   int cnt = 0;
   for(int i = 1; i <= lookbackDays; i++)
     {
      if(i >= ArraySize(highBuf)) break;
      double p = (highBuf[i] + lowBuf[i] + closeBuf[i]) / 3.0;
      double r1 = 2.0 * p - lowBuf[i];
      double s1 = 2.0 * p - highBuf[i];
      sumRange += (r1 - s1);
      cnt++;
     }
   if(cnt == 0 || range0 <= 0)
      return false;

   double avgRange = sumRange / cnt;
   if(avgRange <= 0)
      return false;

   outRatio = range0 / avgRange;
   return (outRatio <= squeezeThreshold);
  }

//+------------------------------------------------------------------+
//| 複合早期警戒判定: Pivotスクイーズ(前日の警戒サイン)を検知した     |
//| シンボル数を数える。SMD_MinAlignedPairs以上あれば「市場全体が     |
//| 方向感を欠いて溜め込んでいる」= 急変前兆の可能性が高いと判断      |
//+------------------------------------------------------------------+
int SMD_CountPivotSqueezeSymbols(const int lookbackDays, const double squeezeThreshold)
  {
   int cnt = 0;
   double ratio;
   for(int i = 0; i < g_SMD_Count; i++)
     {
      if(SMD_CheckPivotSqueeze(g_SMD_States[i].symbol, lookbackDays, squeezeThreshold, ratio))
         cnt++;
     }
   return cnt;
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 単発の急変判定(任意のシンボル・時間足・ATRハンドルで判定)          |
//|                                                                    |
//| g_SMD_States等のグローバル状態には一切依存しない。                  |
//| CCompression_Scanner のように、(通貨ペア×時間足)ごとに個別に       |
//| 急変を判定したい場合に使う。判定ロジックはSMD_CalcSymbolと同じ    |
//| (ATRスパイク かつ ROC Zスコア超過 のAND条件)。                    |
//|                                                                    |
//| atrHandle: 呼び出し側で作成済みのiATRハンドル(毎回作らないこと)   |
//| 戻り値: true=計算成功 / false=データ不足等で判定不能               |
//+------------------------------------------------------------------+
bool SMD_CheckSpike(const string symbol, const ENUM_TIMEFRAMES tf, const int atrHandle,
                    bool &isSpike, bool &isUp, double &atrRatio, double &rocZ)
  {
   isSpike  = false;
   isUp     = false;
   atrRatio = 0.0;
   rocZ     = 0.0;

   if(atrHandle == INVALID_HANDLE)
      return false;

   //--- ATR比: 形成中バーのレンジ / 直近確定ATR ---
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuf) <= 0)
      return false;
   double atrAvg = atrBuf[0];
   if(atrAvg <= 0.0)
      return false;

   double curRange = iHigh(symbol, tf, 0) - iLow(symbol, tf, 0);
   atrRatio = curRange / atrAvg;
   bool atrSpike = (atrRatio >= SMD_ATR_SpikeMult);

   //--- ROCのZスコア ---
   int needed = SMD_ROC_ZLookback + SMD_ROC_Period + 2;
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   if(CopyClose(symbol, tf, 0, needed, closeBuf) < needed)
      return false;

   int n = SMD_ROC_ZLookback;
   double rocArr[];
   ArrayResize(rocArr, n);
   for(int i = 0; i < n; i++)
     {
      double c0 = closeBuf[i];
      double c1 = closeBuf[i + SMD_ROC_Period];
      rocArr[i] = (c1 != 0.0) ? (c0 - c1) / c1 * 100.0 : 0.0;
     }

   double mean = 0.0;
   for(int i = 0; i < n; i++) mean += rocArr[i];
   mean /= n;

   double variance = 0.0;
   for(int i = 0; i < n; i++) variance += MathPow(rocArr[i] - mean, 2);
   variance /= n;
   double stdev = MathSqrt(variance);

   rocZ = (stdev > 0.0) ? (rocArr[0] - mean) / stdev : 0.0;
   isUp = (rocArr[0] > 0.0);
   bool rocSpike = (MathAbs(rocZ) >= SMD_ROC_ZThreshold);

   isSpike = (atrSpike && rocSpike);
   return true;
  }
//+------------------------------------------------------------------+

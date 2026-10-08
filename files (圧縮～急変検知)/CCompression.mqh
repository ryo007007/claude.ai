//+------------------------------------------------------------------+
//|                                            CCompression.mqh       |
//|  CCompression Specification Ver.0.1 準拠                         |
//|                                                                    |
//|  市場の変動幅縮小(Compression)状態を検出する。方向性(上昇/下落/   |
//|  ブレイクアウト)の予測は一切行わない。NORMAL→COMPRESSION→         |
//|  STRONG COMPRESSION→TIGHT COMPRESSION→TRANSITION の状態遷移のみ  |
//|  を観測する。                                                     |
//|                                                                    |
//|  仕様書ではVer.1本番はD1固定だが、本実装は任意のENUM_TIMEFRAMESに  |
//|  対応する汎用版。パーセンタイル方式はスケール非依存なので、        |
//|  理論上M1のような分足にも同じロジックを適用できる(ただし低位足は   |
//|  ノイズが多くScoreが揺れやすい点に注意)。                         |
//|                                                                    |
//|  使い方:                                                          |
//|    CCOMP_Instance inst;                                           |
//|    CCOMP_InitInstance(inst, "USDJPY", PERIOD_D1);                 |
//|    // OnCalculate/OnTimer等で毎回:                                |
//|    if(CCOMP_UpdateInstance(inst))                                 |
//|       Print(CCOMP_StateText(inst.state), " Score=", inst.score);  |
//|    // 終了時:                                                     |
//|    CCOMP_ReleaseInstance(inst);                                   |
//+------------------------------------------------------------------+
#property strict

input group "=== CCompression モジュール設定 ==="
input int CCOMP_Lookback      = 125;  // パーセンタイル算出に使う過去期間数
input int CCOMP_RangePeriod   = 20;   // Range20算出期間
input int CCOMP_ATR_Period    = 14;   // ATR期間
input int CCOMP_BB_Period     = 20;   // ボリンジャーバンド期間
input double CCOMP_BB_Dev     = 2.0;  // ボリンジャーバンド偏差
input int CCOMP_ADX_Period    = 14;   // ADX期間

//--- 状態定義
enum CCOMP_STATE
  {
   CCOMP_NORMAL = 0,
   CCOMP_COMPRESSION,
   CCOMP_STRONG_COMPRESSION,
   CCOMP_TIGHT_COMPRESSION,
   CCOMP_TRANSITION
  };

//--- 1インスタンス = 1(シンボル, 時間足)の組
struct CCOMP_Instance
  {
   string         symbol;
   ENUM_TIMEFRAMES tf;
   int            lookback;

   int            atrHandle;
   int            bbHandle;
   int            adxHandle;

   datetime       lastBarTime;

   //--- 現在値
   double         atrPct;
   double         bbWidthPct;
   double         range20Pct;
   double         adxValue;

   double         atrPctile;     // ATR%の過去分布内パーセンタイル(0-100。低いほど圧縮)
   double         bbPctile;      // BB幅%のパーセンタイル
   double         rangePctile;   // Range20%のパーセンタイル

   int            atrScore;
   int            bbScore;
   int            rangeScore;
   int            adxScore;
   int            score;

   int            prevScore;
   double         prevATRPct;
   double         prevBBWidthPct;

   CCOMP_STATE    state;
   CCOMP_STATE    prevState;
   int            delta;
   int            age;

   bool           ready; // 初期化成功しデータが揃っているか
  };

//+------------------------------------------------------------------+
//| 初期化: ハンドル作成。シンボル・時間足ごとに1回だけ呼ぶ            |
//+------------------------------------------------------------------+
bool CCOMP_InitInstance(CCOMP_Instance &inst, const string symbol, const ENUM_TIMEFRAMES tf,
                         const int lookback = -1)
  {
   inst.symbol   = symbol;
   inst.tf       = tf;
   inst.lookback = (lookback > 0) ? lookback : CCOMP_Lookback;

   inst.lastBarTime    = 0;
   inst.atrPct         = 0.0;
   inst.bbWidthPct      = 0.0;
   inst.range20Pct      = 0.0;
   inst.adxValue        = 0.0;
   inst.atrPctile       = 0.0;
   inst.bbPctile        = 0.0;
   inst.rangePctile     = 0.0;
   inst.atrScore = inst.bbScore = inst.rangeScore = inst.adxScore = inst.score = 0;
   inst.prevScore       = 0;
   inst.prevATRPct      = 0.0;
   inst.prevBBWidthPct  = 0.0;
   inst.state     = CCOMP_NORMAL;
   inst.prevState = CCOMP_NORMAL;
   inst.delta = 0;
   inst.age   = 1;
   inst.ready = false;

   if(!SymbolSelect(symbol, true))
      PrintFormat("CCOMP_InitInstance: シンボル選択失敗 %s", symbol);

   inst.atrHandle = iATR(symbol, tf, CCOMP_ATR_Period);
   inst.bbHandle  = iBands(symbol, tf, CCOMP_BB_Period, 0, CCOMP_BB_Dev, PRICE_CLOSE);
   inst.adxHandle = iADX(symbol, tf, CCOMP_ADX_Period);

   if(inst.atrHandle == INVALID_HANDLE || inst.bbHandle == INVALID_HANDLE || inst.adxHandle == INVALID_HANDLE)
     {
      PrintFormat("CCOMP_InitInstance: ハンドル作成失敗 %s %s", symbol, EnumToString(tf));
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| 終了処理: ハンドル解放                                             |
//+------------------------------------------------------------------+
void CCOMP_ReleaseInstance(CCOMP_Instance &inst)
  {
   if(inst.atrHandle != INVALID_HANDLE) IndicatorRelease(inst.atrHandle);
   if(inst.bbHandle  != INVALID_HANDLE) IndicatorRelease(inst.bbHandle);
   if(inst.adxHandle != INVALID_HANDLE) IndicatorRelease(inst.adxHandle);
  }

//+------------------------------------------------------------------+
//| 過去分布内での現在値のパーセンタイル(0-100)を返す                 |
//+------------------------------------------------------------------+
double CCOMP_Percentile(const double &histArr[], const int n, const double currentVal)
  {
   if(n <= 0) return 50.0;
   int countLE = 0;
   for(int i = 0; i < n; i++)
      if(histArr[i] <= currentVal) countLE++;
   return (double)countLE / (double)n * 100.0;
  }

//--- スコアテーブル(仕様書 Section 3-6)
int CCOMP_ScoreATR(const double pct)
  { if(pct <= 20.0) return 2; if(pct <= 35.0) return 1; return 0; }

int CCOMP_ScoreBB(const double pct)
  { if(pct <= 10.0) return 2; if(pct <= 20.0) return 1; return 0; }

int CCOMP_ScoreRange(const double pct)
  { if(pct <= 20.0) return 2; if(pct <= 40.0) return 1; return 0; }

int CCOMP_ScoreADX(const double adx)
  { if(adx < 15.0) return 2; if(adx < 20.0) return 1; return 0; }

CCOMP_STATE CCOMP_StateFromScore(const int score)
  {
   if(score <= 2) return CCOMP_NORMAL;
   if(score <= 4) return CCOMP_COMPRESSION;
   if(score <= 6) return CCOMP_STRONG_COMPRESSION;
   return CCOMP_TIGHT_COMPRESSION;
  }

string CCOMP_StateText(const CCOMP_STATE st)
  {
   switch(st)
     {
      case CCOMP_NORMAL:             return "NORMAL";
      case CCOMP_COMPRESSION:        return "COMPRESSION";
      case CCOMP_STRONG_COMPRESSION: return "STRONG COMPRESSION";
      case CCOMP_TIGHT_COMPRESSION:  return "TIGHT COMPRESSION";
      case CCOMP_TRANSITION:         return "TRANSITION";
     }
   return "?";
  }

//--- パネル等での短縮表示用
string CCOMP_StateShort(const CCOMP_STATE st)
  {
   switch(st)
     {
      case CCOMP_NORMAL:             return "--";
      case CCOMP_COMPRESSION:        return "C";
      case CCOMP_STRONG_COMPRESSION: return "SC";
      case CCOMP_TIGHT_COMPRESSION:  return "TC";
      case CCOMP_TRANSITION:         return "TR";
     }
   return "?";
  }

//+------------------------------------------------------------------+
//| 更新: 対象時間足の確定足が新しくなった時だけ再計算する。           |
//| 戻り値 true = 新しい確定足があり再計算した / false = 変化なし      |
//+------------------------------------------------------------------+
bool CCOMP_UpdateInstance(CCOMP_Instance &inst)
  {
   datetime barTime = iTime(inst.symbol, inst.tf, 1); // 直近の確定足の時刻
   if(barTime == 0)
      return false; // データ未取得(ヒストリー不足等)
   if(barTime == inst.lastBarTime)
      return false; // 新しい確定足がまだ無い

   int lb = inst.lookback;
   int needBase = lb + 1; // 現在値1 + 過去lb個

   //--- ATR% ---
   double atrBuf[], closeBuf[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(closeBuf, true);
   if(CopyBuffer(inst.atrHandle, 0, 1, needBase, atrBuf) < needBase) return false;
   if(CopyClose(inst.symbol, inst.tf, 1, needBase, closeBuf) < needBase) return false;

   double atrPctArr[];
   ArrayResize(atrPctArr, needBase);
   for(int i = 0; i < needBase; i++)
      atrPctArr[i] = (closeBuf[i] != 0.0) ? atrBuf[i] / closeBuf[i] * 100.0 : 0.0;

   double curATRPct = atrPctArr[0];
   double histATR[];
   ArrayResize(histATR, lb);
   for(int i = 0; i < lb; i++) histATR[i] = atrPctArr[i + 1];
   double atrPercentile = CCOMP_Percentile(histATR, lb, curATRPct);
   int atrScore = CCOMP_ScoreATR(atrPercentile);

   //--- BB Width% ---
   double upBuf[], loBuf[], midBuf[];
   ArraySetAsSeries(upBuf, true);
   ArraySetAsSeries(loBuf, true);
   ArraySetAsSeries(midBuf, true);
   if(CopyBuffer(inst.bbHandle, UPPER_BAND, 1, needBase, upBuf)  < needBase) return false;
   if(CopyBuffer(inst.bbHandle, LOWER_BAND, 1, needBase, loBuf)  < needBase) return false;
   if(CopyBuffer(inst.bbHandle, BASE_LINE,  1, needBase, midBuf) < needBase) return false;

   double bbPctArr[];
   ArrayResize(bbPctArr, needBase);
   for(int i = 0; i < needBase; i++)
      bbPctArr[i] = (midBuf[i] != 0.0) ? (upBuf[i] - loBuf[i]) / midBuf[i] * 100.0 : 0.0;

   double curBBWidthPct = bbPctArr[0];
   double histBB[];
   ArrayResize(histBB, lb);
   for(int i = 0; i < lb; i++) histBB[i] = bbPctArr[i + 1];
   double bbPercentile = CCOMP_Percentile(histBB, lb, curBBWidthPct);
   int bbScore = CCOMP_ScoreBB(bbPercentile);

   //--- Range20% ---
   int rp = CCOMP_RangePeriod;
   int rangeNeed = needBase + (rp - 1);
   double highRaw[], lowRaw[];
   ArraySetAsSeries(highRaw, true);
   ArraySetAsSeries(lowRaw, true);
   if(CopyHigh(inst.symbol, inst.tf, 1, rangeNeed, highRaw) < rangeNeed) return false;
   if(CopyLow(inst.symbol, inst.tf, 1, rangeNeed, lowRaw)   < rangeNeed) return false;

   double rangePctArr[];
   ArrayResize(rangePctArr, needBase);
   for(int j = 0; j < needBase; j++)
     {
      double hh = highRaw[j];
      double ll = lowRaw[j];
      for(int k = 1; k < rp; k++)
        {
         if(highRaw[j + k] > hh) hh = highRaw[j + k];
         if(lowRaw[j + k]  < ll) ll = lowRaw[j + k];
        }
      rangePctArr[j] = (closeBuf[j] != 0.0) ? (hh - ll) / closeBuf[j] * 100.0 : 0.0;
     }

   double curRange20Pct = rangePctArr[0];
   double histRange[];
   ArrayResize(histRange, lb);
   for(int i = 0; i < lb; i++) histRange[i] = rangePctArr[i + 1];
   double rangePercentile = CCOMP_Percentile(histRange, lb, curRange20Pct);
   int rangeScore = CCOMP_ScoreRange(rangePercentile);

   //--- ADX(絶対値) ---
   double adxBuf[];
   ArraySetAsSeries(adxBuf, true);
   if(CopyBuffer(inst.adxHandle, 0, 1, 1, adxBuf) < 1) return false;
   double curADX = adxBuf[0];
   int adxScore = CCOMP_ScoreADX(curADX);

   //--- 合計スコア・状態 ---
   int totalScore = atrScore + bbScore + rangeScore + adxScore;
   CCOMP_STATE baseState = CCOMP_StateFromScore(totalScore);

   //--- TRANSITION判定(仕様書 Section 9: 条件A・B・Cすべて満たす場合のみ) ---
   bool condA = (inst.prevState == CCOMP_STRONG_COMPRESSION || inst.prevState == CCOMP_TIGHT_COMPRESSION);
   bool condB = (totalScore < inst.prevScore);
   bool condC = (curATRPct > inst.prevATRPct) || (curBBWidthPct > inst.prevBBWidthPct);
   CCOMP_STATE finalState = (condA && condB && condC) ? CCOMP_TRANSITION : baseState;

   //--- Delta / Age ---
   inst.delta = totalScore - inst.prevScore;
   inst.age   = (finalState == inst.prevState) ? inst.age + 1 : 1;

   //--- 値を保存 ---
   inst.atrPct      = curATRPct;
   inst.bbWidthPct  = curBBWidthPct;
   inst.range20Pct  = curRange20Pct;
   inst.adxValue    = curADX;
   inst.atrPctile   = atrPercentile;
   inst.bbPctile    = bbPercentile;
   inst.rangePctile = rangePercentile;
   inst.atrScore    = atrScore;
   inst.bbScore     = bbScore;
   inst.rangeScore  = rangeScore;
   inst.adxScore    = adxScore;
   inst.score       = totalScore;
   inst.state       = finalState;

   //--- 次回比較用に保存 ---
   inst.prevScore      = totalScore;
   inst.prevATRPct     = curATRPct;
   inst.prevBBWidthPct = curBBWidthPct;
   inst.prevState      = finalState;

   inst.lastBarTime = barTime;
   inst.ready = true;
   return true;
  }
//+------------------------------------------------------------------+

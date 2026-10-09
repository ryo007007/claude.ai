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
input int CCOMP_ReplayBars    = 200;  // 状態遷移(TRANSITION/Age)を過去から再現する本数

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

//--- 配列の start から n 個を過去分布として、currentVal のパーセンタイルを返す
double CCOMP_PercentileRange(const double &arr[], const int start, const int n, const double currentVal)
  {
   if(n <= 0) return 50.0;
   int countLE = 0;
   for(int i = 0; i < n; i++)
      if(arr[start + i] <= currentVal) countLE++;
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

   //--- 前回の状態を覚えておく方式はやめ、毎回、過去CCOMP_ReplayBars本分の
   //--- 状態遷移を再現して最新の状態を求める(ステートレス方式)。
   //--- こうすると、チャート切替等でインジケーターが読み込み直されても
   //--- TRANSITIONやDelta/Ageが失われない。
   int lb = inst.lookback;
   int rp = CCOMP_RangePeriod;

   //--- 取得できる履歴本数に合わせて、再現する本数Rを決める
   int wantBars = lb + 1 + CCOMP_ReplayBars + (rp - 1);
   double closeBuf[];
   ArraySetAsSeries(closeBuf, true);
   int gotC = CopyClose(inst.symbol, inst.tf, 1, wantBars, closeBuf);
   if(gotC <= 0) return false;

   int R = MathMin(CCOMP_ReplayBars, gotC - (lb + rp));
   if(R < 0) return false;

   int nPts = lb + 1 + R;        // 判定に使う点数(index0=最新確定足 ... 最古=nPts-1)
   int nRaw = nPts + (rp - 1);   // Range20計算に必要な生の本数

   //--- ATR / BB / 高値安値 / ADX を取得 ---
   double atrBuf[], upBuf[], loBuf[], midBuf[], highRaw[], lowRaw[], adxBuf[];
   ArraySetAsSeries(atrBuf, true);
   ArraySetAsSeries(upBuf, true);
   ArraySetAsSeries(loBuf, true);
   ArraySetAsSeries(midBuf, true);
   ArraySetAsSeries(highRaw, true);
   ArraySetAsSeries(lowRaw, true);
   ArraySetAsSeries(adxBuf, true);

   if(CopyBuffer(inst.atrHandle, 0, 1, nPts, atrBuf) < nPts) return false;
   if(CopyBuffer(inst.bbHandle, UPPER_BAND, 1, nPts, upBuf)  < nPts) return false;
   if(CopyBuffer(inst.bbHandle, LOWER_BAND, 1, nPts, loBuf)  < nPts) return false;
   if(CopyBuffer(inst.bbHandle, BASE_LINE,  1, nPts, midBuf) < nPts) return false;
   if(CopyHigh(inst.symbol, inst.tf, 1, nRaw, highRaw) < nRaw) return false;
   if(CopyLow(inst.symbol, inst.tf, 1, nRaw, lowRaw)   < nRaw) return false;
   if(CopyBuffer(inst.adxHandle, 0, 1, R + 1, adxBuf) < R + 1) return false;

   //--- 各足の ATR% / BB幅% / Range20% を算出 ---
   double atrPctArr[], bbPctArr[], rangePctArr[];
   ArrayResize(atrPctArr, nPts);
   ArrayResize(bbPctArr, nPts);
   ArrayResize(rangePctArr, nPts);
   for(int j = 0; j < nPts; j++)
     {
      double c = closeBuf[j];
      atrPctArr[j] = (c != 0.0) ? atrBuf[j] / c * 100.0 : 0.0;
      bbPctArr[j]  = (midBuf[j] != 0.0) ? (upBuf[j] - loBuf[j]) / midBuf[j] * 100.0 : 0.0;

      double hh = highRaw[j];
      double ll = lowRaw[j];
      for(int m = 1; m < rp; m++)
        {
         if(highRaw[j + m] > hh) hh = highRaw[j + m];
         if(lowRaw[j + m]  < ll) ll = lowRaw[j + m];
        }
      rangePctArr[j] = (c != 0.0) ? (hh - ll) / c * 100.0 : 0.0;
     }

   //--- 過去(古い足)から最新の確定足へ向かって状態遷移を再現 ---
   CCOMP_STATE prevState = CCOMP_NORMAL;
   int  prevScore = -1;   // -1 = 比較対象なし(再現の最初の足)
   int  age       = 1;
   int  delta     = 0;
   int  total = 0, sA = 0, sB = 0, sR = 0, sX = 0;
   double pcA = 0.0, pcB = 0.0, pcR = 0.0;
   CCOMP_STATE st = CCOMP_NORMAL;

   for(int k = R; k >= 0; k--)
     {
      // 足kの値を、その1本前から lb 本分の過去分布と比較(k+1 ～ k+lb)
      pcA = CCOMP_PercentileRange(atrPctArr,   k + 1, lb, atrPctArr[k]);
      pcB = CCOMP_PercentileRange(bbPctArr,    k + 1, lb, bbPctArr[k]);
      pcR = CCOMP_PercentileRange(rangePctArr, k + 1, lb, rangePctArr[k]);

      sA = CCOMP_ScoreATR(pcA);
      sB = CCOMP_ScoreBB(pcB);
      sR = CCOMP_ScoreRange(pcR);
      sX = CCOMP_ScoreADX(adxBuf[k]);
      total = sA + sB + sR + sX;

      CCOMP_STATE baseState = CCOMP_StateFromScore(total);

      //--- TRANSITION判定(仕様書 Section 9: 条件A・B・Cすべて満たす場合のみ) ---
      bool condA = (prevState == CCOMP_STRONG_COMPRESSION || prevState == CCOMP_TIGHT_COMPRESSION);
      bool condB = (prevScore >= 0 && total < prevScore);
      bool condC = (atrPctArr[k] > atrPctArr[k + 1]) || (bbPctArr[k] > bbPctArr[k + 1]);
      st = (condA && condB && condC) ? CCOMP_TRANSITION : baseState;

      delta = (prevScore >= 0) ? (total - prevScore) : 0;
      age   = (k == R) ? 1 : ((st == prevState) ? age + 1 : 1);

      prevScore = total;
      prevState = st;
     }

   //--- 最新の確定足(k=0)の結果を保存 ---
   inst.atrPct      = atrPctArr[0];
   inst.bbWidthPct  = bbPctArr[0];
   inst.range20Pct  = rangePctArr[0];
   inst.adxValue    = adxBuf[0];
   inst.atrPctile   = pcA;
   inst.bbPctile    = pcB;
   inst.rangePctile = pcR;
   inst.atrScore    = sA;
   inst.bbScore     = sB;
   inst.rangeScore  = sR;
   inst.adxScore    = sX;
   inst.score       = total;
   inst.state       = st;
   inst.delta       = delta;
   inst.age         = age;

   inst.prevScore      = total;
   inst.prevATRPct     = atrPctArr[0];
   inst.prevBBWidthPct = bbPctArr[0];
   inst.prevState      = st;

   inst.lastBarTime = barTime;
   inst.ready = true;
   return true;
  }
//+------------------------------------------------------------------+

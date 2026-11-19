//+------------------------------------------------------------------+
//|                                      AIPredictorTrainer.mqh        |
//|  事後評価結果からAI重みを学習・更新するエンジン                    |
//|  SignalLogger の results.csv を読み込み、勾配降下法で重み更新    |
//|  HarmonicPattern 対応版（v1.1） / TTM / RSI / Supertrend / Donchian 対応 |
//+------------------------------------------------------------------+
#property strict

//--- AIPredictorEngine を先にインクルード（ENUM_AI_FEATURE 等の定義を使用）
#include "AIPredictorEngine.mqh"

input group "=== AIトレーナー ==="
input bool   AI_Trainer_Enable    = true;   // 学習を有効にする
input int    AI_Trainer_MinSamples= 10;     // 学習に必要な最小サンプル数
input double AI_Trainer_L2Lambda  = 0.001;  // L2正則化係数
input int    AI_Trainer_MaxEpoch  = 100;    // 最大エポック数
input double AI_Trainer_ConvThresh= 0.0001; // 収束束閾値（損失変化）
input string AI_Trainer_ResultDir = "MarketEngines"; // results.csv のディレクトリ

//--- 学習サンプル構造体
struct AI_Sample {
   double features[AI_FEATURE_COUNT];
   int    actualDir;     // 実際の方向 +1=上昇, -1=下落, 0=中立/不確定
   double reward;        // 実現した利益（ATR倍、正）
   double penalty;       // 実現した損失（ATR倍、正）
   double weight;        // サンプル重み（高信頼度ほど重い）
};

AI_Sample g_AI_Samples[];
int       g_AI_SampleCount = 0;

//--- 特徴量重要度ソート用（グローバルに定義）
struct AI_FeatImp {
   string name;
   double absW;
};

//+------------------------------------------------------------------+
//| results.csv パース                                                 |
//+------------------------------------------------------------------+
bool AI_Trainer_LoadResults(const string filename, double &lossOut) {
   string fn = AI_Trainer_ResultDir + "\\" + filename;
   if(!FileIsExist(fn, FILE_COMMON)) {
      Print("AI_Trainer: resultsファイルが見つかりません: ", fn);
      return false;
   }

   int handle = FileOpen(fn, FILE_READ|FILE_CSV|FILE_COMMON, ",");
   if(handle == INVALID_HANDLE) {
      Print("AI_Trainer: resultsファイルオープン失敗: ", fn);
      return false;
   }

   //--- ヘッダー読み飛ばし
   if(!FileIsEnding(handle)) {
      int nCols = 0;
      while(!FileIsEnding(handle) && StringLen(FileReadString(handle)) > 0) nCols++;
   }

   ArrayResize(g_AI_Samples, 0);
   g_AI_SampleCount = 0;
   lossOut = 0.0;

   int row = 0;
   while(!FileIsEnding(handle)) {
      string line = FileReadString(handle);
      if(StringLen(line) == 0) continue;

      // feat 列を探す（ai_dir=... が含まれる部分）
      int featPos = StringFind(line, "ai_dir=");
      if(featPos == -1) continue;

      string feat = StringSubstr(line, featPos);

      // ai_dir を抽出
      int dir = 0;
      int dPos = StringFind(feat, "ai_dir=");
      if(dPos != -1) {
         int dEnd = StringFind(feat, ";", dPos);
         if(dEnd == -1) dEnd = StringLen(feat);
         string dStr = StringSubstr(feat, dPos + 7, dEnd - dPos - 7);
         if(dStr == "up") dir = 1;
         else if(dStr == "down") dir = -1;
         else dir = 0;
      }

      // ai_result を抽出
      int res = 0;
      int rPos = StringFind(feat, "ai_result=");
      if(rPos != -1) {
         int rEnd = StringFind(feat, ";", rPos);
         if(rEnd == -1) rEnd = StringLen(feat);
         string rStr = StringSubstr(feat, rPos + 10, rEnd - rPos - 10);
         if(rStr == "HIT") res = 1;
         else if(rStr == "MISS") res = -1;
      }

      // ai_reward / ai_penalty
      double reward = 0.0, penalty = 0.0;
      int rwPos = StringFind(feat, "ai_reward=");
      if(rwPos != -1) {
         int rwEnd = StringFind(feat, ";", rwPos);
         if(rwEnd == -1) rwEnd = StringLen(feat);
         reward = StringToDouble(StringSubstr(feat, rwPos + 10, rwEnd - rwPos - 10));
      }
      int pnPos = StringFind(feat, "ai_penalty=");
      if(pnPos != -1) {
         int pnEnd = StringFind(feat, ";", pnPos);
         if(pnEnd == -1) pnEnd = StringLen(feat);
         penalty = StringToDouble(StringSubstr(feat, pnPos + 11, pnEnd - pnPos - 11));
      }

      // actualDir の決定
      int actualDir = 0;
      if(res == 1) actualDir = dir;
      else if(res == -1) actualDir = -dir;

      if(actualDir == 0) continue;

      //--- 特徴量ベクトルを再構成
      AI_Sample s;
      ArrayInitialize(s.features, 0.0);
      s.features[AI_BIAS] = 1.0;

      AI_Trainer_ParseFeat(feat, s.features);

      s.actualDir = actualDir;
      s.reward    = reward;
      s.penalty   = penalty;
      s.weight    = 1.0 + reward / MathMax(penalty, 0.001);

      int n = ArraySize(g_AI_Samples);
      ArrayResize(g_AI_Samples, n + 1);
      g_AI_Samples[n] = s;
      g_AI_SampleCount++;
      row++;
   }
   FileClose(handle);

   PrintFormat("AI_Trainer: %d サンプルを読み込みました", g_AI_SampleCount);
   return (g_AI_SampleCount >= AI_Trainer_MinSamples);
}

//+------------------------------------------------------------------+
//| feat 文字列から特徴量を復元（Harmonic対応版）                      |
//+------------------------------------------------------------------+
void AI_Trainer_ParseFeat(const string feat, double &features[]) {
   // EMA
   features[AI_EMA_DIR] = AI_ExtractInt(feat, "ema_dir=", 0);
   features[AI_EMA_EQS] = AI_ExtractDouble(feat, "ema_eqs=", 0.0) / 100.0;
   features[AI_EMA_DEPTH] = AI_ExtractDouble(feat, "ema_depth=", 0.0) / 100.0;
   features[AI_EMA_TREND_STR] = AI_ExtractDouble(feat, "ema_trend_str=", 0.0) / 100.0;
   features[AI_EMA_ALIGN] = AI_ExtractDouble(feat, "ema_align=", 0.0) / 100.0;
   features[AI_EMA_DIV] = AI_ExtractInt(feat, "ema_div=", 0);

   // Compression
   features[AI_COMP_SCORE] = AI_ExtractDouble(feat, "comp_score=", 0.0) / 8.0;
   features[AI_COMP_DELTA] = AI_ExtractDouble(feat, "comp_delta=", 0.0) / 8.0;
   features[AI_COMP_AGE] = MathMin(AI_ExtractDouble(feat, "comp_age=", 0.0), 50.0) / 50.0;
   features[AI_COMP_ATR_PCT] = 1.0 - AI_ExtractDouble(feat, "comp_atr_pct=", 0.5);
   features[AI_COMP_BB_PCT] = 1.0 - AI_ExtractDouble(feat, "comp_bb_pct=", 0.5);
   features[AI_COMP_RANGE_PCT] = 1.0 - AI_ExtractDouble(feat, "comp_range_pct=", 0.5);
   features[AI_COMP_ADX] = AI_ExtractDouble(feat, "comp_adx=", 0.0) / 100.0;
   features[AI_COMP_KC_SQZ] = AI_ExtractBool(feat, "comp_kc_sqz=", false) ? 1.0 : 0.0;
   features[AI_COMP_IS_NR] = AI_ExtractBool(feat, "comp_is_nr=", false) ? 1.0 : 0.0;

   // Ichimoku
   features[AI_ICH_POS] = AI_ExtractInt(feat, "ich_pos=", 0);
   features[AI_ICH_THIN] = AI_ExtractBool(feat, "ich_thin=", false) ? 1.0 : 0.0;
   features[AI_ICH_BREAK_DIR] = AI_ExtractInt(feat, "ich_break_dir=", 0);
   features[AI_ICH_BREAK_AGO] = MathMax(0, 5.0 - AI_ExtractDouble(feat, "ich_break_ago=", 99.0)) / 5.0;
   features[AI_ICH_REL_DIR] = AI_ExtractInt(feat, "ich_rel_dir=", 0);
   features[AI_ICH_BULL_ROLES] = AI_ExtractDouble(feat, "ich_bull_roles=", 0.0) / 3.0;
   features[AI_ICH_BEAR_ROLES] = AI_ExtractDouble(feat, "ich_bear_roles=", 0.0) / 3.0;
   features[AI_ICH_TWIST] = AI_ExtractBool(feat, "ich_twist=", false) ? 1.0 : 0.0;

   // TD
   features[AI_TD_RECENT] = AI_ExtractBool(feat, "td_recent=", false) ? 1.0 : 0.0;
   features[AI_TD_RECENT_DIR] = AI_ExtractInt(feat, "td_recent_dir=", 0);
   int tdKind = AI_ExtractInt(feat, "td_kind=", 0);
   features[AI_TD_KIND] = (tdKind == 13) ? 1.0 : (tdKind == 9 ? 0.5 : 0.0);
   features[AI_TD_PERFECT] = AI_ExtractBool(feat, "td_perfect=", false) ? 1.0 : 0.0;
   features[AI_TD_CD_COUNT] = AI_ExtractDouble(feat, "td_cd_count=", 0.0) / 13.0;

   // Wolfe
   features[AI_WLF_FOUND] = (AI_ExtractString(feat, "wlf=", "0") == "1") ? 1.0 : 0.0;
   features[AI_WLF_STATE] = (AI_ExtractDouble(feat, "wlf_state=", 0.0) == 2) ? 1.0 : 0.5;
   string wlfSig = AI_ExtractString(feat, "sig=", "");
   if(wlfSig == "up") features[AI_WLF_DIR] = 1.0;
   else if(wlfSig == "down") features[AI_WLF_DIR] = -1.0;
   else features[AI_WLF_DIR] = 0.0;
   features[AI_WLF_RR] = MathMin(AI_ExtractDouble(feat, "wlf_rr=", 0.0), 3.0) / 3.0;
   features[AI_WLF_PIN] = AI_ExtractBool(feat, "wlf_pin=", false) ? 1.0 : 0.0;
   features[AI_WLF_ENGULF] = AI_ExtractBool(feat, "wlf_engulf=", false) ? 1.0 : 0.0;

   // Harmonic Pattern
   features[AI_HARM_FOUND] = AI_ExtractBool(feat, "harm_found=", false) ? 1.0 : 0.0;
   int harmType = AI_ExtractInt(feat, "harm_type=", 0);
   features[AI_HARM_TYPE] = (harmType == 2) ? 1.0 : (harmType == 1 ? 0.5 : 0.0);
   int harmDir = AI_ExtractInt(feat, "harm_dir=", 0);
   features[AI_HARM_DIR] = harmDir;
   double harmPRZDist = AI_ExtractDouble(feat, "harm_prz_dist=", 99.0);
   features[AI_HARM_PRZ_DIST] = MathMax(0.0, 1.0 - MathAbs(harmPRZDist) / 3.0);
   int harmAge = AI_ExtractInt(feat, "harm_age=", 99);
   features[AI_HARM_AGE] = MathMax(0.0, 1.0 - MathMin(harmAge, 30) / 30.0);

   // Wick
   features[AI_WICK_DETECTED] = AI_ExtractBool(feat, "wick=", false) ? 1.0 : 0.0;
   features[AI_WICK_UPPER] = AI_ExtractBool(feat, "wick_upper=", false) ? 1.0
                            : (AI_ExtractBool(feat, "wick=", false) ? -1.0 : 0.0);
   features[AI_WICK_RATIO] = AI_ExtractDouble(feat, "wick_ratio=", 0.0);
   features[AI_WICK_MULT] = MathMin(AI_ExtractDouble(feat, "wick_mult=", 0.0), 5.0) / 5.0;

   // RelatedPair
   features[AI_REL_DIR] = AI_ExtractInt(feat, "rel_dir=", 0);
   features[AI_REL_PCT] = AI_ExtractDouble(feat, "rel_pct=", 0.0) / 100.0;
   features[AI_REL_SPIKE_REL] = AI_ExtractDouble(feat, "rel_spike_rel=", 0.0);

   // SuddenMove
   features[AI_SMD_SPIKE] = AI_ExtractBool(feat, "spike=", false) ? 1.0 : 0.0;
   features[AI_SMD_ROBUST_Z] = MathMin(MathAbs(AI_ExtractDouble(feat, "robust_z=", 0.0)), 5.0) / 5.0
                               * (AI_ExtractDouble(feat, "robust_z=", 0.0) > 0 ? 1.0 : -1.0);
   features[AI_SMD_EFFICIENCY] = AI_ExtractDouble(feat, "efficiency=", 0.0);
   features[AI_SMD_ATR_RATIO] = MathMin(AI_ExtractDouble(feat, "atr_ratio=", 0.0), 5.0) / 5.0;
   features[AI_SMD_BROAD_RISK] = AI_ExtractBool(feat, "broad_risk=", false) ? 1.0 : 0.0;

   // EventTime
   int evtMinToNext = AI_ExtractInt(feat, "evt_min=", -1);
   features[AI_EVT_MIN_TO_NEXT] = (evtMinToNext >= 0 && evtMinToNext <= 30) ? (1.0 - evtMinToNext/30.0) : 0.0;
   features[AI_EVT_NEXT_IMP] = AI_ExtractInt(feat, "evt_imp=", 0) / 3.0;
   int evtMinToSess = AI_ExtractInt(feat, "sess_min=", -1);
   features[AI_EVT_MIN_TO_SESS] = (evtMinToSess >= 0 && evtMinToSess <= 60) ? (1.0 - evtMinToSess/60.0) : 0.0;
   features[AI_EVT_SCORE] = AI_ExtractDouble(feat, "evt_score=", 0.0);
   int evtMinSince = AI_ExtractInt(feat, "evt_since=", -1);
   features[AI_EVT_MIN_SINCE_LAST] = (evtMinSince >= 0 && evtMinSince <= 10) ? (1.0 - evtMinSince/10.0) : 0.0;

   // TTM Squeeze
   features[AI_TTM_SQZ] = AI_ExtractBool(feat, "ttm_sqz=", false) ? 1.0 : 0.0;
   features[AI_TTM_RELEASED] = AI_ExtractBool(feat, "ttm_rel=", false) ? 1.0 : 0.0;
   features[AI_TTM_MOM_DIR] = AI_ExtractInt(feat, "ttm_dir=", 0);
   features[AI_TTM_MOM] = MathMax(-1.0, MathMin(1.0, AI_ExtractDouble(feat, "ttm_mom=", 0.0) * 100.0));

   //--- Supertrend
   features[AI_ST_DIR] = AI_ExtractInt(feat, "st_dir=", 0);
   features[AI_ST_FLIP] = AI_ExtractBool(feat, "st_flip=", false) ? 1.0 : 0.0;
   features[AI_ST_BARS] = MathMin(1.0, AI_ExtractDouble(feat, "st_bars=", 0.0) / 20.0);

   //--- Donchian (新規追加)
   features[AI_DON_DIR] = AI_ExtractInt(feat, "don_dir=", 0);
   features[AI_DON_POS] = AI_ExtractInt(feat, "don_pos=", 0);
   features[AI_DON_BREAK] = AI_ExtractBool(feat, "don_up=", false) || AI_ExtractBool(feat, "don_dn=", false) ? 1.0 : 0.0;
}

//+------------------------------------------------------------------+
//| 補助: feat 文字列から値を抽出                                      |
//+------------------------------------------------------------------+
string AI_ExtractString(const string feat, const string key, const string defVal) {
   int pos = StringFind(feat, key);
   if(pos == -1) return defVal;
   int start = pos + StringLen(key);
   int end = StringFind(feat, ";", start);
   if(end == -1) end = StringLen(feat);
   return StringSubstr(feat, start, end - start);
}

int AI_ExtractInt(const string feat, const string key, const int defVal) {
   return (int)StringToInteger(AI_ExtractString(feat, key, IntegerToString(defVal)));
}

double AI_ExtractDouble(const string feat, const string key, const double defVal) {
   return StringToDouble(AI_ExtractString(feat, key, DoubleToString(defVal, 6)));
}

bool AI_ExtractBool(const string feat, const string key, const bool defVal) {
   string s = AI_ExtractString(feat, key, defVal ? "1" : "0");
   return (s == "1" || s == "true");
}

//+------------------------------------------------------------------+
//| シグモイドとその導関数                                              |
//+------------------------------------------------------------------+
double AI_Trainer_Sigmoid(double z) {
   if(z > 10.0)  return 1.0;
   if(z < -10.0) return 0.0;
   return 1.0 / (1.0 + MathExp(-z));
}

//+------------------------------------------------------------------+
//| 損失関数（重み付き交差エントロピー + L2）                          |
//+------------------------------------------------------------------+
double AI_Trainer_Loss(const AI_Sample &s[], const double &w[], int n, double l2) {
   double loss = 0.0;
   for(int i = 0; i < n; i++) {
      double z = 0.0;
      for(int j = 0; j < AI_FEATURE_COUNT; j++) {
         z += w[j] * s[i].features[j];
      }
      double p = AI_Trainer_Sigmoid(z);
      double y = (s[i].actualDir > 0) ? 1.0 : 0.0;
      double eps = 1e-10;
      loss += s[i].weight * (-(y * MathLog(p + eps) + (1.0 - y) * MathLog(1.0 - p + eps)));
   }
   loss /= n;
   double l2term = 0.0;
   for(int j = 1; j < AI_FEATURE_COUNT; j++) {
      l2term += w[j] * w[j];
   }
   loss += 0.5 * l2 * l2term;
   return loss;
}

//+------------------------------------------------------------------+
//| 勾配計算                                                           |
//+------------------------------------------------------------------+
void AI_Trainer_Gradient(const AI_Sample &s[], const double &w[], int n,
                         double l2, double &grad[]) {
   ArrayInitialize(grad, 0.0);

   for(int i = 0; i < n; i++) {
      double z = 0.0;
      for(int j = 0; j < AI_FEATURE_COUNT; j++) {
         z += w[j] * s[i].features[j];
      }
      double p = AI_Trainer_Sigmoid(z);
      double y = (s[i].actualDir > 0) ? 1.0 : 0.0;
      double err = (p - y) * s[i].weight;

      for(int j = 0; j < AI_FEATURE_COUNT; j++) {
         grad[j] += err * s[i].features[j];
      }
   }

   for(int j = 0; j < AI_FEATURE_COUNT; j++) {
      grad[j] /= n;
      if(j > 0) grad[j] += l2 * w[j];
   }
}

//+------------------------------------------------------------------+
//| 学習実行                                                           |
//+------------------------------------------------------------------+
bool AI_Trainer_Train(const string resultFile, double &finalLoss) {
   if(!AI_Trainer_Enable) {
      Print("AI_Trainer: 無効です");
      return false;
   }

   double prevLoss = 0.0;
   if(!AI_Trainer_LoadResults(resultFile, prevLoss)) {
      Print("AI_Trainer: 学習データの読み込みに失敗しました");
      return false;
   }

   if(g_AI_SampleCount < AI_Trainer_MinSamples) {
      PrintFormat("AI_Trainer: サンプル不足 (%d < %d)", g_AI_SampleCount, AI_Trainer_MinSamples);
      return false;
   }

   double w[AI_FEATURE_COUNT];
   ArrayCopy(w, g_AI_Weights);

   double grad[AI_FEATURE_COUNT];
   double bestW[AI_FEATURE_COUNT];
   double bestLoss = 1e300;

   PrintFormat("AI_Trainer: 学習開始 サンプル=%d エポックmax=%d 特徴量=%d",
               g_AI_SampleCount, AI_Trainer_MaxEpoch, AI_FEATURE_COUNT);

   for(int epoch = 0; epoch < AI_Trainer_MaxEpoch; epoch++) {
      double loss = AI_Trainer_Loss(g_AI_Samples, w, g_AI_SampleCount, AI_Trainer_L2Lambda);

      if(loss < bestLoss) {
         bestLoss = loss;
         ArrayCopy(bestW, w);
      }

      if(epoch > 0 && MathAbs(prevLoss - loss) < AI_Trainer_ConvThresh) {
         PrintFormat("AI_Trainer: 収束しました epoch=%d loss=%.6f", epoch, loss);
         break;
      }
      prevLoss = loss;

      AI_Trainer_Gradient(g_AI_Samples, w, g_AI_SampleCount, AI_Trainer_L2Lambda, grad);

      for(int j = 0; j < AI_FEATURE_COUNT; j++) {
         w[j] -= AI_LearningRate * grad[j];
      }

      if(epoch % 10 == 0) {
         PrintFormat("AI_Trainer: epoch=%d loss=%.6f", epoch, loss);
      }
   }

   ArrayCopy(g_AI_Weights, bestW);
   finalLoss = bestLoss;

   PrintFormat("AI_Trainer: 学習完了 最終loss=%.6f", bestLoss);

   if(AI_SaveWeights(AI_WeightFile)) {
      Print("AI_Trainer: 重みを保存しました: ", AI_WeightFile);
   }

   AI_Trainer_PrintImportance();
   return true;
}

//+------------------------------------------------------------------+
//| 特徴量重要度を出力                                                 |
//+------------------------------------------------------------------+
void AI_Trainer_PrintImportance() {
   Print("=== AI 特徴量重要度（重み絶対値）===");

   AI_FeatImp imps[];
   ArrayResize(imps, AI_FEATURE_COUNT);

   for(int i = 0; i < AI_FEATURE_COUNT; i++) {
      imps[i].name = g_AI_FeatureNames[i];
      imps[i].absW = MathAbs(g_AI_Weights[i]);
   }

   // バブルソート
   for(int i = 0; i < AI_FEATURE_COUNT - 1; i++) {
      for(int j = i + 1; j < AI_FEATURE_COUNT; j++) {
         if(imps[j].absW > imps[i].absW) {
            AI_FeatImp tmp = imps[i];
            imps[i] = imps[j];
            imps[j] = tmp;
         }
      }
   }

   for(int i = 0; i < MathMin(20, AI_FEATURE_COUNT); i++) {
      int idx = AI_Trainer_FindIndex(imps[i].name);
      PrintFormat("  %2d. %-20s w=%+.4f", i+1, imps[i].name,
                  (idx >= 0) ? g_AI_Weights[idx] : 0.0);
   }
}

//+------------------------------------------------------------------+
//| 特徴量名からインデックスを検索                                     |
//+------------------------------------------------------------------+
int AI_Trainer_FindIndex(const string name) {
   for(int i = 0; i < AI_FEATURE_COUNT; i++) {
      if(g_AI_FeatureNames[i] == name) return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| オンライン学習（1件ずつ重みを更新）                                |
//+------------------------------------------------------------------+
void AI_Trainer_OnlineUpdate(const AI_Input &in, int actualDir, double reward, double penalty) {
   if(!AI_Trainer_Enable) return;
   if(actualDir == 0) return;

   double features[AI_FEATURE_COUNT];
   AI_InputToFeatures(in, features);

   double z = AI_ComputeZ(features);
   double p = AI_Trainer_Sigmoid(z);
   double y = (actualDir > 0) ? 1.0 : 0.0;
   double err = (p - y) * (1.0 + reward / MathMax(penalty, 0.001));

   for(int j = 0; j < AI_FEATURE_COUNT; j++) {
      g_AI_Weights[j] -= AI_LearningRate * (err * features[j]
                         + AI_Trainer_L2Lambda * (j > 0 ? g_AI_Weights[j] : 0.0));
   }

   static int updateCount = 0;
   updateCount++;
   if(updateCount % 100 == 0) {
      AI_SaveWeights(AI_WeightFile);
   }
}
//+------------------------------------------------------------------+
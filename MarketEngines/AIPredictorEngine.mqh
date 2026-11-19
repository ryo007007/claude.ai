//+------------------------------------------------------------------+
//|                                      AIPredictorEngine.mqh       |
//|  軽量機械学習予測エンジン（線形回帰＋シグモイド）                 |
//|  全圧縮状態で常時予測。案B。                                     |
//|  統合エンジン: CCompression, EMA, SMD, Wick, RelatedPair,         |
//|               EventTime, Ichimoku, TD, Wolfe, Harmonic, Volume, TTM, RSI, Supertrend, Donchian |
//+------------------------------------------------------------------+
#property strict

//--- 入力グループ
input group "=== AI予測エンジン ==="
input bool   AI_Enable          = true;   // AI予測を有効にする
input int    AI_MinConfidence   = 50;     // 一覧に表示する最低信頼度(%)
input int    AI_HighConfidence  = 80;     // 高信頼度とみなす閾値(%)
input bool   AI_AlertOnHighConf = true;   // 高信頼度でアラート
input bool   AI_LogToSLG        = true;   // SignalLoggerに記録
input string AI_ModelVersion    = "ml_v1.6"; // モデルバージョン (Donchian統合版)
input string AI_WeightFile      = "AIWeights.csv"; // 重みファイル名
input double AI_LearningRate    = 0.01;   // 学習率（Trainer使用時）

//--- 特徴量インデックス定数 (Donchian統合版)
enum ENUM_AI_FEATURE {
   AI_BIAS = 0,          // バイアス
   AI_EMA_DIR,           // EMA方向
   AI_EMA_EQS,           // EMA品質
   AI_EMA_DEPTH,         // EMA深さ
   AI_EMA_TREND_STR,     // EMAトレンド強度
   AI_EMA_ALIGN,         // EMAアライメント
   AI_EMA_DIV,           // EMAダイバージェンス
   AI_COMP_SCORE,        // 圧縮スコア
   AI_COMP_DELTA,        // 圧縮変化
   AI_COMP_AGE,          // 圧縮継続年齢
   AI_COMP_ATR_PCT,      // ATRパーセンタイル
   AI_COMP_BB_PCT,       // BBパーセンタイル
   AI_COMP_RANGE_PCT,    // Rangeパーセンタイル
   AI_COMP_ADX,          // ADX
   AI_COMP_KC_SQZ,       // KCスクイーズ
   AI_COMP_IS_NR,        // Narrow Range
   AI_ICH_POS,           // 一目位置
   AI_ICH_THIN,          // 薄い雲
   AI_ICH_BREAK_DIR,     // 雲抜け方向
   AI_ICH_BREAK_AGO,     // 雲抜け経過
   AI_ICH_REL_DIR,       // 一目解除方向
   AI_ICH_BULL_ROLES,    // 三役好転
   AI_ICH_BEAR_ROLES,    // 三役逆転
   AI_ICH_TWIST,         // ねじれ予告
   AI_TD_RECENT,         // TD直近完了
   AI_TD_RECENT_DIR,     // TD完了方向
   AI_TD_KIND,           // TD種別（9/13）
   AI_TD_PERFECT,        // TDパーフェト
   AI_TD_CD_COUNT,       // TDカウントダウン
   AI_WLF_FOUND,         // Wolfe成立
   AI_WLF_STATE,         // Wolfe状態
   AI_WLF_DIR,           // Wolfe方向
   AI_WLF_RR,            // Wolfe RR
   AI_WLF_PIN,           // Wolfeピンバー
   AI_WLF_ENGULF,        // Wolfe包み足
   AI_HARM_FOUND,        // Harmonic成立
   AI_HARM_TYPE,         // Harmonic種別
   AI_HARM_DIR,          // Harmonic方向
   AI_HARM_PRZ_DIST,     // PRZ距離（ATR倍）
   AI_HARM_AGE,          // D点経過
   AI_WICK_DETECTED,     // 髭検知
   AI_WICK_UPPER,        // 上髭
   AI_WICK_RATIO,        // 髭比率
   AI_WICK_MULT,         // 髭倍率
   AI_REL_DIR,           // 関連ペア方向
   AI_REL_PCT,           // 関連ペア予兆
   AI_REL_SPIKE_REL,     // 関連ペア急変
   AI_SMD_SPIKE,         // 急変フラグ
   AI_SMD_ROBUST_Z,      // 急変Zスコア
   AI_SMD_EFFICIENCY,    // 急変効率
   AI_SMD_ATR_RATIO,     // 急変ATR倍率
   AI_SMD_BROAD_RISK,    // 広がり
   AI_EVT_MIN_TO_NEXT,   // 次指標まで
   AI_EVT_NEXT_IMP,      // 次指標重要度
   AI_EVT_MIN_TO_SESS,   // 次開場まで
   AI_EVT_SCORE,         // イベントスコア
   AI_EVT_MIN_SINCE_LAST,// 直前指標経過
   AI_VOL_STATE,         // 出来高 3段階 (+1/0/-1)
   AI_VOL_RATIO,         // 出来高 比率 (0〜)
   AI_VOL_SPIKE,         // 出来高 Vol↑連続本数
   AI_TTM_SQZ,           // スクイーズ中か
   AI_TTM_RELEASED,      // 直近で解除したか
   AI_TTM_MOM_DIR,       // モメンタム方向
   AI_TTM_MOM,           // モメンタム値
   AI_RSI_NOW,           // RSI 現在値
   AI_RSI_DIV_DIR,       // ダイバージェンス方向
   AI_RSI_RECENT,        // 直近ダイバージェンスか
   AI_RSI_STR,           // ダイバージェンス強さ
   AI_ST_DIR,            // Supertrend方向
   AI_ST_FLIP,           // 直近で反転したか
   AI_ST_BARS,           // トレンド継続本数
   AI_DON_DIR,           // Donchianブレイク方向
   AI_DON_POS,           // 価格の位置 (上半分 / 下半分)
   AI_DON_BREAK,         // 直近でブレイクしたか
   AI_FEATURE_COUNT      // 特徴量総数 (=72)
};

//--- 入力構造体（全エンジン統合）
struct AI_Input {
   // CCompression
   int    compState; int compScore; int compDelta; int compAge;
   double compATRPctile; double compBBPctile; double compRangePctile;
   double compADX; bool compKCSqueeze; bool compIsNR;
   // EMA
   int    emaDir; int emaEQS; int emaDepth; int emaTrendStr;
   int    emaAlignScore; int emaDiv; string emaZone;
   // SuddenMove
   bool   smdSpike; double smdRobustZ; double smdEfficiency;
   double smdATRRatio; bool smdBroadRisk; string smdRiskMode;
   // Wick
   bool   wickDetected; bool wickUpper; double wickRatio; double wickMult;
   // RelatedPair
   double relPct; int relDir; double relSpikeRel; int relNRelated;
   // EventTime
   int    evtMinToNext; int evtNextImp; int evtMinToSession;
   double evtScore; int evtMinSinceLast;
   // Volume
   int    volState;      // +1=Vol↑ 0=Vol→ -1=Vol↓
   double volRatio;      // volNow / volAvg
   int    volSpikeBars;  // Vol↑連続本数
   // TTM Squeeze
   bool   ttmSqueeze;
   bool   ttmReleased;
   int    ttmMomDir;
   double ttmMomentum;
   // RSI Divergence
   double rsiNow;
   int    rsiDivDir;
   bool   rsiRecent;
   int    rsiStrength;
   // Supertrend
   int    stDir;
   bool   stFlipped;
   int    stBars;
   // Donchian (新規)
   int    donDir;
   int    donPos;
   bool   donBreak;
   // Ichimoku
   int    ichPos; bool ichThin; int ichBreakDir; int ichBreakAgo;
   int    ichRelDir; int ichBullRoles; int ichBearRoles; bool ichTwistAhead;
   // TD
   bool   tdRecent; int tdRecentDir; int tdRecentKind; int tdRecentAgo;
   bool   tdLastPerfect; int tdCDCount;
   // Wolfe
   bool   wlfFound; int wlfState; int wlfDir; double wlfRR;
   bool   wlfPinBar; bool wlfEngulf;
   // Harmonic Pattern
   bool   harmFound;       // パターン成立
   int    harmType;        // 0=なし, 1=ABCD, 2=Gartley
   int    harmDir;         // +1=買い, -1=売り
   double harmPRZDist;     // PRZと現在値の距離（ATR倍、0=現在値がPRZ）
   int    harmAge;         // D点からの経過本数（0=最新）
   string harmName;        // パターン名（ログ用）
};

//--- 出力構造体
struct AI_Prediction {
   int    direction;     // +1=上昇, -1=下落, 0=中立
   double confidence;    // 0.0〜100.0
   double zScore;        // 生の線形出力（学習用）
   string rationale;     // 判断根拠タグ
   string modelVersion;
};

//--- グローバル重み配列
double g_AI_Weights[AI_FEATURE_COUNT];
string g_AI_FeatureNames[AI_FEATURE_COUNT];
bool   g_AI_WeightsLoaded = false;

//+------------------------------------------------------------------+
//| 初期化                                                             |
//+------------------------------------------------------------------+
void AI_InitFeatureNames() {
   g_AI_FeatureNames[AI_BIAS]           = "bias";
   g_AI_FeatureNames[AI_EMA_DIR]        = "ema_dir";
   g_AI_FeatureNames[AI_EMA_EQS]        = "ema_eqs";
   g_AI_FeatureNames[AI_EMA_DEPTH]      = "ema_depth";
   g_AI_FeatureNames[AI_EMA_TREND_STR]  = "ema_trend_str";
   g_AI_FeatureNames[AI_EMA_ALIGN]      = "ema_align";
   g_AI_FeatureNames[AI_EMA_DIV]        = "ema_div";
   g_AI_FeatureNames[AI_COMP_SCORE]     = "comp_score";
   g_AI_FeatureNames[AI_COMP_DELTA]     = "comp_delta";
   g_AI_FeatureNames[AI_COMP_AGE]       = "comp_age";
   g_AI_FeatureNames[AI_COMP_ATR_PCT]   = "comp_atr_pct";
   g_AI_FeatureNames[AI_COMP_BB_PCT]    = "comp_bb_pct";
   g_AI_FeatureNames[AI_COMP_RANGE_PCT] = "comp_range_pct";
   g_AI_FeatureNames[AI_COMP_ADX]       = "comp_adx";
   g_AI_FeatureNames[AI_COMP_KC_SQZ]    = "comp_kc_sqz";
   g_AI_FeatureNames[AI_COMP_IS_NR]     = "comp_is_nr";
   g_AI_FeatureNames[AI_ICH_POS]        = "ich_pos";
   g_AI_FeatureNames[AI_ICH_THIN]       = "ich_thin";
   g_AI_FeatureNames[AI_ICH_BREAK_DIR]  = "ich_break_dir";
   g_AI_FeatureNames[AI_ICH_BREAK_AGO]  = "ich_break_ago";
   g_AI_FeatureNames[AI_ICH_REL_DIR]    = "ich_rel_dir";
   g_AI_FeatureNames[AI_ICH_BULL_ROLES] = "ich_bull_roles";
   g_AI_FeatureNames[AI_ICH_BEAR_ROLES] = "ich_bear_roles";
   g_AI_FeatureNames[AI_ICH_TWIST]      = "ich_twist";
   g_AI_FeatureNames[AI_TD_RECENT]      = "td_recent";
   g_AI_FeatureNames[AI_TD_RECENT_DIR]  = "td_recent_dir";
   g_AI_FeatureNames[AI_TD_KIND]        = "td_kind";
   g_AI_FeatureNames[AI_TD_PERFECT]     = "td_perfect";
   g_AI_FeatureNames[AI_TD_CD_COUNT]    = "td_cd_count";
   g_AI_FeatureNames[AI_WLF_FOUND]      = "wlf_found";
   g_AI_FeatureNames[AI_WLF_STATE]      = "wlf_state";
   g_AI_FeatureNames[AI_WLF_DIR]        = "wlf_dir";
   g_AI_FeatureNames[AI_WLF_RR]         = "wlf_rr";
   g_AI_FeatureNames[AI_WLF_PIN]        = "wlf_pin";
   g_AI_FeatureNames[AI_WLF_ENGULF]     = "wlf_engulf";
   g_AI_FeatureNames[AI_HARM_FOUND]     = "harm_found";
   g_AI_FeatureNames[AI_HARM_TYPE]      = "harm_type";
   g_AI_FeatureNames[AI_HARM_DIR]       = "harm_dir";
   g_AI_FeatureNames[AI_HARM_PRZ_DIST]  = "harm_prz_dist";
   g_AI_FeatureNames[AI_HARM_AGE]       = "harm_age";
   g_AI_FeatureNames[AI_WICK_DETECTED]  = "wick_detected";
   g_AI_FeatureNames[AI_WICK_UPPER]     = "wick_upper";
   g_AI_FeatureNames[AI_WICK_RATIO]     = "wick_ratio";
   g_AI_FeatureNames[AI_WICK_MULT]      = "wick_mult";
   g_AI_FeatureNames[AI_REL_DIR]        = "rel_dir";
   g_AI_FeatureNames[AI_REL_PCT]        = "rel_pct";
   g_AI_FeatureNames[AI_REL_SPIKE_REL]  = "rel_spike_rel";
   g_AI_FeatureNames[AI_SMD_SPIKE]      = "smd_spike";
   g_AI_FeatureNames[AI_SMD_ROBUST_Z]   = "smd_robust_z";
   g_AI_FeatureNames[AI_SMD_EFFICIENCY] = "smd_efficiency";
   g_AI_FeatureNames[AI_SMD_ATR_RATIO]  = "smd_atr_ratio";
   g_AI_FeatureNames[AI_SMD_BROAD_RISK] = "smd_broad_risk";
   g_AI_FeatureNames[AI_EVT_MIN_TO_NEXT]= "evt_min_to_next";
   g_AI_FeatureNames[AI_EVT_NEXT_IMP]   = "evt_next_imp";
   g_AI_FeatureNames[AI_EVT_MIN_TO_SESS]= "evt_min_to_sess";
   g_AI_FeatureNames[AI_EVT_SCORE]      = "evt_score";
   g_AI_FeatureNames[AI_EVT_MIN_SINCE_LAST] = "evt_min_since_last";
   g_AI_FeatureNames[AI_VOL_STATE]      = "vol_state";
   g_AI_FeatureNames[AI_VOL_RATIO]      = "vol_ratio";
   g_AI_FeatureNames[AI_VOL_SPIKE]      = "vol_spike";
   g_AI_FeatureNames[AI_TTM_SQZ]        = "ttm_sqz";
   g_AI_FeatureNames[AI_TTM_RELEASED]   = "ttm_released";
   g_AI_FeatureNames[AI_TTM_MOM_DIR]    = "ttm_mom_dir";
   g_AI_FeatureNames[AI_TTM_MOM]        = "ttm_mom";
   g_AI_FeatureNames[AI_RSI_NOW]        = "rsi_now";
   g_AI_FeatureNames[AI_RSI_DIV_DIR]    = "rsi_div_dir";
   g_AI_FeatureNames[AI_RSI_RECENT]     = "rsi_recent";
   g_AI_FeatureNames[AI_RSI_STR]        = "rsi_str";
   g_AI_FeatureNames[AI_ST_DIR]         = "st_dir";
   g_AI_FeatureNames[AI_ST_FLIP]        = "st_flip";
   g_AI_FeatureNames[AI_ST_BARS]        = "st_bars";
   g_AI_FeatureNames[AI_DON_DIR]        = "don_dir";
   g_AI_FeatureNames[AI_DON_POS]        = "don_pos";
   g_AI_FeatureNames[AI_DON_BREAK]      = "don_break";
}

//+------------------------------------------------------------------+
//| デフォルト重みの設定（ルールベースで初期化）                       |
//+------------------------------------------------------------------+
void AI_SetDefaultWeights() {
   ArrayInitialize(g_AI_Weights, 0.0);

   g_AI_Weights[AI_BIAS]           =  0.00;
   g_AI_Weights[AI_EMA_DIR]        = +0.60;
   g_AI_Weights[AI_EMA_EQS]        = +0.25;
   g_AI_Weights[AI_EMA_DEPTH]      = +0.10;
   g_AI_Weights[AI_EMA_TREND_STR]  = +0.15;
   g_AI_Weights[AI_EMA_ALIGN]      = +0.20;
   g_AI_Weights[AI_EMA_DIV]        = +0.30;
   g_AI_Weights[AI_COMP_SCORE]     = +0.05;
   g_AI_Weights[AI_COMP_DELTA]     = +0.03;
   g_AI_Weights[AI_COMP_AGE]       = -0.02;
   g_AI_Weights[AI_COMP_ATR_PCT]   = +0.04;
   g_AI_Weights[AI_COMP_BB_PCT]    = +0.03;
   g_AI_Weights[AI_COMP_RANGE_PCT] = +0.03;
   g_AI_Weights[AI_COMP_ADX]       = +0.02;
   g_AI_Weights[AI_COMP_KC_SQZ]    = +0.05;
   g_AI_Weights[AI_COMP_IS_NR]     = +0.03;
   g_AI_Weights[AI_ICH_POS]        = +0.25;
   g_AI_Weights[AI_ICH_THIN]       = +0.10;
   g_AI_Weights[AI_ICH_BREAK_DIR]  = +0.35;
   g_AI_Weights[AI_ICH_BREAK_AGO]  = -0.05;
   g_AI_Weights[AI_ICH_REL_DIR]    = +0.30;
   g_AI_Weights[AI_ICH_BULL_ROLES] = +0.15;
   g_AI_Weights[AI_ICH_BEAR_ROLES] = -0.15;
   g_AI_Weights[AI_ICH_TWIST]      = +0.08;
   g_AI_Weights[AI_TD_RECENT]      = +0.10;
   g_AI_Weights[AI_TD_RECENT_DIR]  = -0.40;
   g_AI_Weights[AI_TD_KIND]        = +0.15;
   g_AI_Weights[AI_TD_PERFECT]     = +0.10;
   g_AI_Weights[AI_TD_CD_COUNT]    = +0.03;
   g_AI_Weights[AI_WLF_FOUND]      = +0.10;
   g_AI_Weights[AI_WLF_STATE]      = +0.15;
   g_AI_Weights[AI_WLF_DIR]        = +0.25;
   g_AI_Weights[AI_WLF_RR]         = +0.10;
   g_AI_Weights[AI_WLF_PIN]        = +0.10;
   g_AI_Weights[AI_WLF_ENGULF]     = +0.10;
   //--- Harmonic Pattern
   g_AI_Weights[AI_HARM_FOUND]     = +0.15;
   g_AI_Weights[AI_HARM_TYPE]      = +0.05;
   g_AI_Weights[AI_HARM_DIR]       = +0.25;
   g_AI_Weights[AI_HARM_PRZ_DIST]  = -0.10;
   g_AI_Weights[AI_HARM_AGE]       = -0.08;
   g_AI_Weights[AI_WICK_DETECTED]  = +0.10;
   g_AI_Weights[AI_WICK_UPPER]     = -0.25;
   g_AI_Weights[AI_WICK_RATIO]     = +0.15;
   g_AI_Weights[AI_WICK_MULT]      = +0.05;
   g_AI_Weights[AI_REL_DIR]        = +0.20;
   g_AI_Weights[AI_REL_PCT]        = +0.15;
   g_AI_Weights[AI_REL_SPIKE_REL]  = +0.10;
   g_AI_Weights[AI_SMD_SPIKE]      = +0.10;
   g_AI_Weights[AI_SMD_ROBUST_Z]   = +0.10;
   g_AI_Weights[AI_SMD_EFFICIENCY] = +0.15;
   g_AI_Weights[AI_SMD_ATR_RATIO]  = +0.05;
   g_AI_Weights[AI_SMD_BROAD_RISK] = +0.10;
   g_AI_Weights[AI_EVT_MIN_TO_NEXT]= -0.10;
   g_AI_Weights[AI_EVT_NEXT_IMP]   = -0.15;
   g_AI_Weights[AI_EVT_MIN_TO_SESS]= +0.05;
   g_AI_Weights[AI_EVT_SCORE]      = +0.10;
   g_AI_Weights[AI_EVT_MIN_SINCE_LAST] = -0.08;
   //--- Volume
   g_AI_Weights[AI_VOL_STATE]      = +0.25; // Vol↑は順方向に効く
   g_AI_Weights[AI_VOL_RATIO]      = +0.10; // 比率が高いほど強い
   g_AI_Weights[AI_VOL_SPIKE]      = +0.05; // 連続は少しだけ
   //--- TTM Squeeze
   g_AI_Weights[AI_TTM_SQZ]        = -0.05;      // スクイーズ中は方向なし (少しマイナス)
   g_AI_Weights[AI_TTM_RELEASED]   = +0.15; // 解除は方向ありの合図
   g_AI_Weights[AI_TTM_MOM_DIR]    = +0.30;  // モメンタム方向は強い
   g_AI_Weights[AI_TTM_MOM]        = +0.10;      // モメンタムの大きさ
   //--- RSI Divergence
   g_AI_Weights[AI_RSI_NOW]        = 0.0;        // RSI自体は方向なし (70超え / 30割れは別で見る)
   g_AI_Weights[AI_RSI_DIV_DIR]    = +0.30;  // ダイバージェンス方向は強い
   g_AI_Weights[AI_RSI_RECENT]     = +0.10;   // 直近なら少し強い
   g_AI_Weights[AI_RSI_STR]        = +0.10;      // 強さ
   //--- Supertrend
   g_AI_Weights[AI_ST_DIR]         = +0.25;   // トレンド方向は強い
   g_AI_Weights[AI_ST_FLIP]        = +0.15;  // 直近の反転は合図
   g_AI_Weights[AI_ST_BARS]        =  0.0;     // 継続本数は方向なし (長すぎると疲弊もある)
   //--- Donchian (新規)
   g_AI_Weights[AI_DON_DIR]        = +0.25;   // ブレイク方向は強い
   g_AI_Weights[AI_DON_POS]        = +0.10;   // 価格の位置
   g_AI_Weights[AI_DON_BREAK]      = +0.15; // 直近ブレイクは合図
}

//+------------------------------------------------------------------+
//| 重みのファイル保存                                                 |
//+------------------------------------------------------------------+
bool AI_SaveWeights(const string filename) {
   string fn = "MarketEngines\\" + filename;
   int handle = FileOpen(fn, FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_SHARE_WRITE, ",");
   if(handle == INVALID_HANDLE) return false;

   FileWrite(handle, "feature", "weight");
   for(int i = 0; i < AI_FEATURE_COUNT; i++) {
      FileWrite(handle, g_AI_FeatureNames[i], DoubleToString(g_AI_Weights[i], 6));
   }
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| 重みのファイル読み込み                                             |
//+------------------------------------------------------------------+
bool AI_LoadWeights(const string filename) {
   string fn = "MarketEngines\\" + filename;
   if(!FileIsExist(fn, FILE_COMMON)) return false;

   int handle = FileOpen(fn, FILE_READ|FILE_CSV|FILE_COMMON, ",");
   if(handle == INVALID_HANDLE) return false;

   if(!FileIsEnding(handle)) {
      FileReadString(handle); FileReadString(handle);
   }

   while(!FileIsEnding(handle)) {
      string name = FileReadString(handle);
      string sval = FileReadString(handle);
      if(StringLen(name) == 0) continue;

      for(int i = 0; i < AI_FEATURE_COUNT; i++) {
         if(g_AI_FeatureNames[i] == name) {
            g_AI_Weights[i] = StringToDouble(sval);
            break;
         }
      }
   }
   FileClose(handle);
   g_AI_WeightsLoaded = true;
   return true;
}

//+------------------------------------------------------------------+
//| 重み初期化（OnInitで呼ぶ）                                         |
//+------------------------------------------------------------------+
void AI_InitWeights() {
   AI_InitFeatureNames();
   AI_SetDefaultWeights();

   if(StringLen(AI_WeightFile) > 0) {
      if(!AI_LoadWeights(AI_WeightFile)) {
         AI_SaveWeights(AI_WeightFile);
      }
   }
}

//+------------------------------------------------------------------+
//| 入力を特徴量ベクトルに変換（正規化済み）                           |
//+------------------------------------------------------------------+
void AI_InputToFeatures(const AI_Input &in, double &features[]) {
   ArrayResize(features, AI_FEATURE_COUNT);

   features[AI_BIAS]           = 1.0;
   features[AI_EMA_DIR]        = in.emaDir;
   features[AI_EMA_EQS]        = in.emaEQS / 100.0;
   features[AI_EMA_DEPTH]      = in.emaDepth / 100.0;
   features[AI_EMA_TREND_STR]  = in.emaTrendStr / 100.0;
   features[AI_EMA_ALIGN]      = in.emaAlignScore / 100.0;
   features[AI_EMA_DIV]        = in.emaDiv;
   features[AI_COMP_SCORE]     = in.compScore / 8.0;
   features[AI_COMP_DELTA]     = in.compDelta / 8.0;
   features[AI_COMP_AGE]       = MathMin(in.compAge, 50) / 50.0;
   features[AI_COMP_ATR_PCT]   = 1.0 - in.compATRPctile;
   features[AI_COMP_BB_PCT]    = 1.0 - in.compBBPctile;
   features[AI_COMP_RANGE_PCT] = 1.0 - in.compRangePctile;
   features[AI_COMP_ADX]       = in.compADX / 100.0;
   features[AI_COMP_KC_SQZ]    = in.compKCSqueeze ? 1.0 : 0.0;
   features[AI_COMP_IS_NR]     = in.compIsNR ? 1.0 : 0.0;
   features[AI_ICH_POS]        = in.ichPos;
   features[AI_ICH_THIN]       = in.ichThin ? 1.0 : 0.0;
   features[AI_ICH_BREAK_DIR]  = in.ichBreakDir;
   features[AI_ICH_BREAK_AGO]  = MathMax(0, 5 - in.ichBreakAgo) / 5.0;
   features[AI_ICH_REL_DIR]    = in.relDir;
   features[AI_ICH_BULL_ROLES] = in.ichBullRoles / 3.0;
   features[AI_ICH_BEAR_ROLES] = in.ichBearRoles / 3.0;
   features[AI_ICH_TWIST]      = in.ichTwistAhead ? 1.0 : 0.0;
   features[AI_TD_RECENT]      = in.tdRecent ? 1.0 : 0.0;
   features[AI_TD_RECENT_DIR]  = in.tdRecent ? in.tdRecentDir : 0.0;
   features[AI_TD_KIND]        = (in.tdRecentKind == 13) ? 1.0 : (in.tdRecentKind == 9 ? 0.5 : 0.0);
   features[AI_TD_PERFECT]     = in.tdLastPerfect ? 1.0 : 0.0;
   features[AI_TD_CD_COUNT]    = in.tdCDCount / 13.0;
   features[AI_WLF_FOUND]      = in.wlfFound ? 1.0 : 0.0;
   features[AI_WLF_STATE]      = (in.wlfState == 2) ? 1.0 : (in.wlfState == 1 ? 0.5 : 0.0);
   features[AI_WLF_DIR]        = in.wlfFound ? in.wlfDir : 0.0;
   features[AI_WLF_RR]         = MathMin(in.wlfRR, 3.0) / 3.0;
   features[AI_WLF_PIN]        = in.wlfPinBar ? 1.0 : 0.0;
   features[AI_WLF_ENGULF]     = in.wlfEngulf ? 1.0 : 0.0;
   //--- Harmonic
   features[AI_HARM_FOUND]     = in.harmFound ? 1.0 : 0.0;
   features[AI_HARM_TYPE]      = in.harmFound ? (in.harmType == 2 ? 1.0 : (in.harmType == 1 ? 0.5 : 0.0)) : 0.0;
   features[AI_HARM_DIR]       = in.harmFound ? in.harmDir : 0.0;
   features[AI_HARM_PRZ_DIST]  = in.harmFound ? MathMax(0.0, 1.0 - MathAbs(in.harmPRZDist) / 3.0) : 0.0;
   features[AI_HARM_AGE]       = in.harmFound ? MathMax(0.0, 1.0 - MathMin(in.harmAge, 30) / 30.0) : 0.0;
   features[AI_WICK_DETECTED]  = in.wickDetected ? 1.0 : 0.0;
   features[AI_WICK_UPPER]     = in.wickDetected ? (in.wickUpper ? 1.0 : -1.0) : 0.0;
   features[AI_WICK_RATIO]     = in.wickRatio;
   features[AI_WICK_MULT]      = MathMin(in.wickMult, 5.0) / 5.0;
   features[AI_REL_DIR]        = in.relDir;
   features[AI_REL_PCT]        = in.relPct / 100.0;
   features[AI_REL_SPIKE_REL]  = in.relSpikeRel;
   features[AI_SMD_SPIKE]      = in.smdSpike ? 1.0 : 0.0;
   features[AI_SMD_ROBUST_Z]   = MathMin(MathAbs(in.smdRobustZ), 5.0) / 5.0 * (in.smdRobustZ > 0 ? 1.0 : -1.0);
   features[AI_SMD_EFFICIENCY] = in.smdEfficiency;
   features[AI_SMD_ATR_RATIO]  = MathMin(in.smdATRRatio, 5.0) / 5.0;
   features[AI_SMD_BROAD_RISK] = in.smdBroadRisk ? 1.0 : 0.0;
   features[AI_EVT_MIN_TO_NEXT]= (in.evtMinToNext >= 0 && in.evtMinToNext <= 30) ? (1.0 - in.evtMinToNext/30.0) : 0.0;
   features[AI_EVT_NEXT_IMP]   = in.evtNextImp / 3.0;
   features[AI_EVT_MIN_TO_SESS]= (in.evtMinToSession >= 0 && in.evtMinToSession <= 60) ? (1.0 - in.evtMinToSession/60.0) : 0.0;
   features[AI_EVT_SCORE]      = in.evtScore;
   features[AI_EVT_MIN_SINCE_LAST] = (in.evtMinSinceLast >= 0 && in.evtMinSinceLast <= 10) ? (1.0 - in.evtMinSinceLast/10.0) : 0.0;
   //--- Volume
   features[AI_VOL_STATE]      = in.volState;
   features[AI_VOL_RATIO]      = MathMin(in.volRatio, 3.0) / 3.0;
   features[AI_VOL_SPIKE]      = MathMin(in.volSpikeBars, 5) / 5.0;
   //--- TTM Squeeze
   features[AI_TTM_SQZ]        = in.ttmSqueeze ? 1.0 : 0.0;
   features[AI_TTM_RELEASED]   = in.ttmReleased ? 1.0 : 0.0;
   features[AI_TTM_MOM_DIR]    = in.ttmMomDir;
   features[AI_TTM_MOM]        = MathMax(-1.0, MathMin(1.0, in.ttmMomentum * 100.0));
   //--- RSI Divergence
   features[AI_RSI_NOW]        = (in.rsiNow - 50.0) / 50.0;
   features[AI_RSI_DIV_DIR]    = in.rsiDivDir;
   features[AI_RSI_RECENT]     = in.rsiRecent ? 1.0 : 0.0;
   features[AI_RSI_STR]        = in.rsiStrength / 100.0;
   //--- Supertrend
   features[AI_ST_DIR]         = in.stDir;
   features[AI_ST_FLIP]        = in.stFlipped ? 1.0 : 0.0;
   features[AI_ST_BARS]        = MathMin(1.0, in.stBars / 20.0);
   //--- Donchian (新規)
   features[AI_DON_DIR]        = in.donDir;
   features[AI_DON_POS]        = in.donPos;
   features[AI_DON_BREAK]      = in.donBreak ? 1.0 : 0.0;
}

//+------------------------------------------------------------------+
//| 線形結合（Zスコア計算）                                            |
//+------------------------------------------------------------------+
double AI_ComputeZ(const double &features[]) {
   double z = 0.0;
   for(int i = 0; i < AI_FEATURE_COUNT; i++) {
      z += g_AI_Weights[i] * features[i];
   }
   return z;
}

//+------------------------------------------------------------------+
//| シグモイド                                                         |
//+------------------------------------------------------------------+
double AI_Sigmoid(double z) {
   if(z > 10.0)  return 1.0;
   if(z < -10.0) return 0.0;
   return 1.0 / (1.0 + MathExp(-z));
}

//+------------------------------------------------------------------+
//| 根拠文字列の構築                                                   |
//+------------------------------------------------------------------+
string AI_BuildRationale(const AI_Input &in, const double &features[]) {
   string r = "";

   // EMA
   if(in.emaDir != 0 && MathAbs(g_AI_Weights[AI_EMA_DIR] * features[AI_EMA_DIR]) >= 0.05) {
      r += (in.emaDir > 0 ? "EMA_BUY," : "EMA_SELL,");
   }
   if(in.emaEQS >= 70 && MathAbs(g_AI_Weights[AI_EMA_EQS] * features[AI_EMA_EQS]) >= 0.03) {
      r += "EMA_HIGHQ,";
   }

   // 圧縮
   if(in.compScore >= 6 && g_AI_Weights[AI_COMP_SCORE] * features[AI_COMP_SCORE] >= 0.02) {
      r += "COMP_DEEP,";
   }
   if(in.compKCSqueeze) r += "KC_SQZ,";
   if(in.compIsNR) r += "NR7,";

   // 一目
   if(in.ichRelDir != 0 && MathAbs(g_AI_Weights[AI_ICH_REL_DIR] * features[AI_ICH_REL_DIR]) >= 0.03) {
      r += (in.ichRelDir > 0 ? "ICHI_UP," : "ICHI_DOWN,");
   }
   if(in.ichBullRoles == 3) r += "ICHI_3BULL,";
   if(in.ichBearRoles == 3) r += "ICHI_3BEAR,";
   if(in.ichTwistAhead) r += "ICHI_TWIST,";

   // TD
   if(in.tdRecent && in.tdRecentAgo <= 3) {
      if(in.tdRecentKind == 13) {
         r += (in.tdRecentDir > 0 ? "TD13_SELL," : "TD13_BUY,");
      } else if(in.tdRecentKind == 9) {
         r += (in.tdRecentDir > 0 ? "TD9_SELL," : "TD9_BUY,");
      }
      if(in.tdLastPerfect) r += "TD_PERFECT,";
   }
   if(in.tdCDCount >= 10) r += "TD_CD_NEAR,";

   // Wolfe
   if(in.wlfFound && in.wlfState == 2 && in.wlfRR >= 1.5) {
      r += (in.wlfDir > 0 ? "WOLFE_BUY," : "WOLFE_SELL,");
      if(in.wlfPinBar) r += "WOLFE_PIN,";
      if(in.wlfEngulf) r += "WOLFE_ENGULF,";
   }

   // Harmonic Pattern
   if(in.harmFound && in.harmAge <= 5) {
      r += in.harmName + "_" + (in.harmDir > 0 ? "BUY," : "SELL,");
      if(MathAbs(in.harmPRZDist) <= 0.5) r += "HARM_PRZ_NEAR,";
   }

   // Volume
   if(in.volState > 0 && in.volRatio >= 1.5)
      r += "VOL_UP,";
   else if(in.volState < 0)
      r += "VOL_DOWN,";

   // TTM Squeeze
   if(in.ttmReleased && in.ttmMomDir != 0)
      r += (in.ttmMomDir > 0 ? "TTM_REL_UP," : "TTM_REL_DOWN,");
   else if(in.ttmSqueeze)
      r += "TTM_SQZ,";

   // RSI Divergence
   if(in.rsiRecent && in.rsiDivDir != 0)
      r += (in.rsiDivDir > 0 ? "RSI_DIV_BUY," : "RSI_DIV_SELL,");

   // Supertrend
   if(in.stFlipped && in.stDir != 0)
      r += (in.stDir > 0 ? "ST_FLIP_UP," : "ST_FLIP_DOWN,");
   else if(in.stDir != 0)
      r += (in.stDir > 0 ? "ST_UP," : "ST_DOWN,");

   // Donchian
   if(in.donBreak && in.donDir != 0)
      r += (in.donDir > 0 ? "DON_BREAK_UP," : "DON_BREAK_DOWN,");
   else if(in.donPos != 0)
      r += (in.donPos > 0 ? "DON_UPPER," : "DON_LOWER,");

   // 髭
   if(in.wickDetected && in.wickRatio >= 0.5) {
      r += (in.wickUpper ? "WICK_REJECT_UP," : "WICK_REJECT_DOWN,");
   }

   // 関連ペア
   if(in.relDir != 0 && in.relPct >= 50.0) {
      r += (in.relDir > 0 ? "REL_UP," : "REL_DOWN,");
   }

   // 急変
   if(in.smdBroadRisk) {
      r += (in.smdRiskMode == "riskoff" ? "BROAD_RISCOFF," : "BROAD_RISKON,");
   }

   // イベント
   if(in.evtMinToNext >= 0 && in.evtMinToNext <= 15 && in.evtNextImp >= 3) {
      r += "EVT_NEAR_HI,";
   }

   // 末尾のカンマを除去
   if(StringLen(r) > 0) {
      r = StringSubstr(r, 0, StringLen(r) - 1);
   }

   return r;
}

//+------------------------------------------------------------------+
//| メイン予測関数                                                     |
//+------------------------------------------------------------------+
bool AI_Predict(const AI_Input &in, AI_Prediction &out) {
   if(!AI_Enable) {
      out.direction = 0;
      out.confidence = 0.0;
      out.zScore = 0.0;
      out.rationale = "DISABLED";
      out.modelVersion = AI_ModelVersion;
      return false;
   }

   double features[];
   AI_InputToFeatures(in, features);

   double z = AI_ComputeZ(features);
   double prob = AI_Sigmoid(z);

   // 信頼度と方向の判定
   double conf = MathAbs(prob - 0.5) * 2.0 * 100.0;

   if(prob > 0.55 && conf >= AI_MinConfidence) {
      out.direction = 1;
      out.confidence = conf;
   } else if(prob < 0.45 && conf >= AI_MinConfidence) {
      out.direction = -1;
      out.confidence = conf;
   } else {
      out.direction = 0;
      out.confidence = conf;
   }

   out.zScore = z;
   out.rationale = AI_BuildRationale(in, features);
   out.modelVersion = AI_ModelVersion;

   return true;
}

//+------------------------------------------------------------------+
//| 方向記号                                                           |
//+------------------------------------------------------------------+
string AI_DirMark(const int dir) {
   if(dir > 0) return "▲";
   if(dir < 0) return "▼";
   return "━";
}

//+------------------------------------------------------------------+
//| SignalLogger用特徴量文字列                                         |
//+------------------------------------------------------------------+
string AI_Feat(const AI_Prediction &p) {
   return StringFormat("ai_dir=%s;ai_conf=%.1f;ai_z=%.4f;ai_basis=%s;ai_ver=%s",
                       p.direction > 0 ? "up" : (p.direction < 0 ? "down" : "flat"),
                       p.confidence, p.zScore, p.rationale, p.modelVersion);
}

//+------------------------------------------------------------------+
//| 詳細パネル用テキスト                                               |
//+------------------------------------------------------------------+
string AI_DetailText(const AI_Input &in, const AI_Prediction &p) {
   string s = StringFormat("AI予測: %s %.1f%%\n", AI_DirMark(p.direction), p.confidence);
   s += StringFormat("Z=%.3f | Model=%s\n", p.zScore, p.modelVersion);
   s += "根拠:\n";

   string r = p.rationale;
   while(StringLen(r) > 0) {
      int pos = StringFind(r, ",");
      string tok;
      if(pos == -1) {
         tok = r; r = "";
      } else {
         tok = StringSubstr(r, 0, pos);
         r = StringSubstr(r, pos + 1);
      }
      if(StringLen(tok) > 0) {
         s += "  " + tok + "\n";
      }
   }

   s += StringFormat("\n圧縮: score=%d age=%d\n", in.compScore, in.compAge);
   s += StringFormat("EMA: dir=%d eqs=%d zone=%s\n", in.emaDir, in.emaEQS, in.emaZone);
   s += StringFormat("一目: pos=%d break=%d roles=%d/%d\n", in.ichPos, in.ichBreakDir, in.ichBullRoles, in.ichBearRoles);
   s += StringFormat("TD: recent=%d kind=%d dir=%d\n", in.tdRecent ? 1 : 0, in.tdRecentKind, in.tdRecentDir);
   s += StringFormat("Wolfe: found=%d state=%d dir=%d rr=%.2f\n", in.wlfFound ? 1 : 0, in.wlfState, in.wlfDir, in.wlfRR);
   s += StringFormat("Harmonic: found=%d type=%d dir=%d przDist=%.2f age=%d\n",
                       in.harmFound ? 1 : 0, in.harmType, in.harmDir, in.harmPRZDist, in.harmAge);
   s += StringFormat("Volume: state=%d ratio=%.2f spike=%d\n",
                       in.volState, in.volRatio, in.volSpikeBars);
   s += StringFormat("TTM: sqz=%d released=%d momDir=%d mom=%.5f\n",
                       in.ttmSqueeze ? 1 : 0, in.ttmReleased ? 1 : 0,
                       in.ttmMomDir, in.ttmMomentum);
   s += StringFormat("RSI: now=%.1f div=%d recent=%d str=%d\n",
                       in.rsiNow, in.rsiDivDir, in.rsiRecent ? 1 : 0, in.rsiStrength);
   s += StringFormat("ST: dir=%d flip=%d bars=%d\n",
                       in.stDir, in.stFlipped ? 1 : 0, in.stBars);
   s += StringFormat("DON: dir=%d pos=%d break=%d\n",
                       in.donDir, in.donPos, in.donBreak ? 1 : 0);

   return s;
}
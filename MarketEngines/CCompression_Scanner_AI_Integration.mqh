//+------------------------------------------------------------------+
//|                                      CCompression_Scanner_AI_Integration.mqh |
//|  CCompression_Scanner.mq5 への AI 予測統合モジュール               |
//|                                                                     |
//|  【使い方】                                                         |
//|  1. 既存の CCompression_Scanner.mq5 をバックアップ                  |
//|  2. 既存の #include 群の最後に以下を追加:                          |
//|       #include "MarketEngines/AIPredictorEngine.mqh"               |
//|       #include "MarketEngines/AIPredictorTrainer.mqh"              |
//|       #include "MarketEngines/CCompression_Scanner_AI_Integration.mqh" |
//|  3. 既存の input 群の最後に AI パラメータが自動追加される          |
//|  4. OnInit()    の最後に AI_Init() を呼び出し                      |
//|  5. OnDeinit()  の最後に AI_Deinit() を呼び出し                    |
//|  6. UpdateAndDraw() の行表示ループ内に AI_UpdateRow() を呼び出し   |
//|  7. UpdateAndDraw() の最後に AI_UpdatePanel() を呼び出し           |
//+------------------------------------------------------------------+
#property strict

//--- 既存のグローバル変数を extern 参照（実際のスキャナーで定義済み）
// 注: これらは既存の CCompression_Scanner.mq5 で定義されている変数です
//     この .mqh をインクルードする際は、既存変数と名前が一致していることを確認してください

// extern 相当の参照（MQL5ではグローバルスコープで再宣言不可のため、
// このファイルでは既存変数を前提とした関数のみを提供します）

//+------------------------------------------------------------------+
//| AI 統合初期化（OnInit の最後に呼び出し）                           |
//+------------------------------------------------------------------+
void AI_Init()
  {
   if(!AI_Enable) return;

   AI_InitWeights();
   AI_DetailPanelMulti_Init();

   Print("AI予測エンジン初期化完了。重みファイル=", AI_WeightFile,
         " 読込=", g_AI_WeightsLoaded ? "OK" : "DEFAULT");

   if(AI_Trainer_Enable)
     {
      double finalLoss = 0.0;
      if(AI_Trainer_Train("results.csv", finalLoss))
        {
         PrintFormat("AIトレーナー: 学習完了 loss=%.6f", finalLoss);
        }
     }
  }

//+------------------------------------------------------------------+
//| AI 統合解放（OnDeinit の最後に呼び出し）                           |
//+------------------------------------------------------------------+
void AI_Deinit()
  {
   if(!AI_Enable) return;

   AI_DetailPanelMulti_Deinit();

   if(AI_Trainer_Enable)
     {
      if(AI_SaveWeights(AI_WeightFile))
        {
         Print("AIトレーナー: 重みを保存しました: ", AI_WeightFile);
        }
     }
  }

//+------------------------------------------------------------------+
//| AI_Input 構築関数（既存エンジン出力を統合）                        |
//| 既存の g_scan[], g_comp[] 等を参照                               |
//+------------------------------------------------------------------+
bool AI_BuildInput(const int idx, AI_Input &out)
  {
   //--- CCompression（既存の g_comp[] を参照）
   // 注: 存の CompressionResult 構造体のフィールド名に合わせて調整してください
   out.compState       = g_comp[idx].state;
   out.compScore       = g_comp[idx].score;
   out.compDelta       = g_comp[idx].delta;
   out.compAge         = g_comp[idx].age;
   out.compATRPctile   = g_comp[idx].atrPctile;
   out.compBBPctile    = g_comp[idx].bbPctile;
   out.compRangePctile = g_comp[idx].rangePctile;
   out.compADX         = g_comp[idx].adx;
   out.compKCSqueeze   = g_comp[idx].kcSqueeze;
   out.compIsNR        = g_comp[idx].isNR;

   //--- EMA Alignment
   EMA_ALIGN_Result ema;
   if(EMA_Compute(g_scan[idx].symbol, g_scan[idx].tf, ema))
     {
      out.emaDir         = ema.dir;
      out.emaEQS         = ema.eqs;
      out.emaDepth       = ema.depthScore;
      out.emaTrendStr    = ema.trendStrength;
      out.emaAlignScore  = ema.alignmentScore;
      out.emaDiv         = ema.divergence;
      out.emaZone        = ema.zoneLabel;
     }
   else
     {
      out.emaDir = 0; out.emaEQS = 0; out.emaDepth = 0;
      out.emaTrendStr = 0; out.emaAlignScore = 0; out.emaDiv = 0;
      out.emaZone = "";
     }

   //--- SuddenMoveDetector
   SMD_Result smd;
   if(SMD_Compute(g_scan[idx].symbol, g_scan[idx].tf, smd))
     {
      out.smdSpike    = smd.isSpike;
      out.smdRobustZ  = smd.robustZ;
      out.smdEfficiency = smd.efficiency;
      out.smdATRRatio = smd.atrRatio;
      out.smdBroadRisk= smd.broadRisk;
      out.smdRiskMode = smd.riskMode;
     }
   else
     {
      out.smdSpike = false; out.smdRobustZ = 0;
      out.smdEfficiency = 0; out.smdATRRatio = 0;
      out.smdBroadRisk = false; out.smdRiskMode = "none";
     }

   //--- WickDetector
   WICK_Result wick;
   if(WICK_Compute(g_scan[idx].symbol, g_scan[idx].tf, wick))
     {
      out.wickDetected = wick.isWick;
      out.wickUpper    = wick.isUpper;
      out.wickRatio    = wick.wickRatio;
      out.wickMult     = wick.multiplier;
     }
   else
     {
      out.wickDetected = false; out.wickUpper = false;
      out.wickRatio = 0; out.wickMult = 0;
     }

   //--- RelatedPairEngine
   REL_Result rel;
   if(REL_Compute(g_scan[idx].symbol, g_scan[idx].tf, rel))
     {
      out.relPct      = rel.pct;
      out.relDir      = rel.dir;
      out.relSpikeRel = rel.spikeRel;
      out.relNRelated = rel.nRelated;
     }
   else
     {
      out.relPct = 0; out.relDir = 0;
      out.relSpikeRel = 0; out.relNRelated = 0;
     }

   //--- EventTimeEngine
   EVT_Info evt;
   if(EVT_Compute(g_scan[idx].symbol, g_scan[idx].tf, evt))
     {
      out.evtMinToNext    = evt.minToNext;
      out.evtNextImp      = evt.nextImp;
      out.evtMinToSession = evt.minToSession;
      out.evtScore        = evt.score;
      out.evtMinSinceLast = evt.minSinceLast;
     }
   else
     {
      out.evtMinToNext = -1; out.evtNextImp = 0;
      out.evtMinToSession = -1; out.evtScore = 0;
      out.evtMinSinceLast = -1;
     }

   //--- IchimokuEngine
   ICH_Result ich;
   if(ICH_Compute(g_scan[idx].symbol, g_scan[idx].tf, ich))
     {
      out.ichPos        = ich.pos;
      out.ichThin       = ich.thin;
      out.ichBreakDir   = ich.breakDir;
      out.ichBreakAgo   = ich.breakAgo;
      out.ichRelDir     = ich.relDir;
      out.ichBullRoles  = ich.bullRoles;
      out.ichBearRoles  = ich.bearRoles;
      out.ichTwistAhead = ich.twistAhead;
     }
   else
     {
      out.ichPos = 0; out.ichThin = false;
      out.ichBreakDir = 0; out.ichBreakAgo = -1;
      out.ichRelDir = 0; out.ichBullRoles = 0;
      out.ichBearRoles = 0; out.ichTwistAhead = false;
     }

   //--- TDSequentialEngine
   TDS_Result td;
   if(TDS_Compute(g_scan[idx].symbol, g_scan[idx].tf, td))
     {
      out.tdRecent      = td.recent;
      out.tdRecentDir   = td.recentDir;
      out.tdRecentKind  = td.recentKind;
      out.tdRecentAgo   = td.recentAgo;
      out.tdLastPerfect = td.lastPerfect;
      out.tdCDCount     = td.cdCount;
     }
   else
     {
      out.tdRecent = false; out.tdRecentDir = 0;
      out.tdRecentKind = 0; out.tdRecentAgo = -1;
      out.tdLastPerfect = false; out.tdCDCount = 0;
     }

   //--- WolfeWaveEngine
   WLF_Result wlf;
   if(WLF_Compute(g_scan[idx].symbol, g_scan[idx].tf, wlf))
     {
      out.wlfFound  = wlf.found;
      out.wlfState  = wlf.state;
      out.wlfDir    = wlf.dir;
      out.wlfRR     = wlf.rr;
      out.wlfPinBar = wlf.pinBar;
      out.wlfEngulf = wlf.engulf;
     }
   else
     {
      out.wlfFound = false; out.wlfState = 0;
      out.wlfDir = 0; out.wlfRR = 0;
      out.wlfPinBar = false; out.wlfEngulf = false;
     }

   //--- HarmonicPatternEngine
   HARM_Result harm;
   if(HARM_Compute(g_scan[idx].symbol, g_scan[idx].tf, harm))
     {
      out.harmFound   = harm.found;
      out.harmType    = (harm.type == HARM_GARTLEY) ? 2 : (harm.type == HARM_ABCD ? 1 : 0);
      out.harmDir     = harm.direction;
      out.harmPRZDist = 0.0;
      out.harmAge     = 0;
      out.harmName    = harm.patternName;

      double currentClose = iClose(g_scan[idx].symbol, g_scan[idx].tf, 0);
      double atr = HARM_GetATR(g_scan[idx].symbol, g_scan[idx].tf, 14);
      if(atr > 0.0)
         out.harmPRZDist = (currentClose - harm.PRZ) / atr;

      out.harmAge = iBarShift(g_scan[idx].symbol, g_scan[idx].tf, harm.tD, true);
      if(out.harmAge < 0) out.harmAge = 0;
     }
   else
     {
      out.harmFound   = false;
      out.harmType    = 0;
      out.harmDir     = 0;
      out.harmPRZDist = 0.0;
      out.harmAge     = 0;
      out.harmName    = "";
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 行のAI予測更新（UpdateAndDraw の行ループ内で呼び出し）             |
//|                                                                    |
//| 引数:                                                              |
//|   idx      - g_candIdx[r] の値（スキャナーインデックス）          |
//|   kind     - g_candKind[r] の値（0=圧縮/発射行）                  |
//|   io_line  - 入出力: 行テキス文字列（AI予測を追加）              |
//|   io_rowClr- 入出力: 行の色（高信頼度で変更）                      |
//|   io_feat  - 入出力: SignalLogger用 feat 文字列                    |
//|                                                                    |
//| 戻り値: AI予測を追加したかどうか                                   |
//+------------------------------------------------------------------+
bool AI_UpdateRow(const int idx, const int kind, string &io_line, color &io_rowClr, string &io_feat)
  {
   if(!AI_Enable) return false;
   if(kind != 0) return false;  // 圧縮・発射行のみ

   AI_Input aiIn;
   AI_Prediction aiPred;

   if(!AI_BuildInput(idx, aiIn)) return false;
   if(!AI_Predict(aiIn, aiPred)) return false;

   // 行テキストにAI予測を追加
   if(aiPred.confidence >= AI_MinConfidence)
      io_line += StringFormat(" AI%s%.0f%%", AI_DirMark(aiPred.direction), aiPred.confidence);
   else
      io_line += " AI━";

   // 高信頼度で行の色を変更
   if(aiPred.confidence >= AI_HighConfidence && aiPred.direction != 0)
     {
      if(aiPred.direction > 0) io_rowClr = clrDodgerBlue;
      else                     io_rowClr = clrHotPink;
     }

   // SignalLogger へ追記
   if(AI_LogToSLG)
     {
      string aiFeat = AI_Feat(aiPred);
      if(StringLen(io_feat) > 0) io_feat += ";";
      io_feat += aiFeat;
     }

   // SignalAlert 高信頼度通知
   if(AI_AlertOnHighConf && aiPred.confidence >= AI_HighConfidence && aiPred.direction != 0)
     {
      string aiKey = StringFormat("CCOMP_AI_%s_%d_AI_%s",
                     g_scan[idx].symbol, g_scan[idx].tf, AI_ModelVersion);
      if(SAL_FireOnce(aiKey, (double)g_scan[idx].lastBarTime))
        {
         SAL_Queue(StringFormat("【AI予測】%s %s AI%s %.0f%% [%s]",
                                   g_scan[idx].symbol, TFName(g_scan[idx].tf),
                                   AI_DirMark(aiPred.direction),
                                   aiPred.confidence, aiPred.rationale));
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//| DetailPanel 更新（UpdateAndDraw の最後に呼び出し）                 |
//+------------------------------------------------------------------+
void AI_UpdatePanel()
  {
   if(!AI_Enable) return;
   if(g_scanCount <= 0) return;

   // 最初の圧縮行を探して表示
   int detailIdx = -1;
   for(int i = 0; i < g_scanCount; i++)
     {
      if(g_scan[i].candKind == 0) { detailIdx = i; break; }
     }
   if(detailIdx < 0) return;

   AI_DetailPanelMulti_Update(detailIdx);
  }

//+------------------------------------------------------------------+
//| 事後評価コールバック（SignalLogger から呼び出し）                  |
//+------------------------------------------------------------------+
void AI_OnPostEvaluate(const int idx, int actualDir, double reward, double penalty)
  {
   if(!AI_Trainer_Enable) return;
   if(idx < 0 || idx >= g_scanCount) return;

   AI_Input aiIn;
   if(!AI_BuildInput(idx, aiIn)) return;

   AI_Trainer_OnlineUpdate(aiIn, actualDir, reward, penalty);
  }
//+------------------------------------------------------------------+

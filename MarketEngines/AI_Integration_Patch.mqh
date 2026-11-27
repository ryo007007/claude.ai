//+------------------------------------------------------------------+
//|                                          AI_Integration_Patch.mqh  |
//|  CCompression_Scanner v1.52 用 AI統合パッチ (Option 2)              |
//|                                                                     |
//|  【設計】                                                          |
//|  ・エンジンを再計算しない。スキャナーが計算済みの結果を使い回す    |
//|    g_scan / g_td / g_ich / g_wlf / g_harm / g_emaAlign / g_spike |
//|    / g_don                                                         |
//|  ・詳細パネルは「今のチャート」の idx を使う                      |
//|  ・存在しない AI_DetailPanelMulti_* は呼ばない                    |
//|  ・results.csv の学習はしない (SignalLogger と未接続のため)       |
//+------------------------------------------------------------------+

//--- AI 用グローバル変数
AI_Input      g_LastAIInputs[];
AI_Prediction g_LastAIPreds[];

//+------------------------------------------------------------------+
//| AI 統合初期化                                                     |
//+------------------------------------------------------------------+
void AI_Init()
  {
   if(!AI_Enable) return;

   ArrayResize(g_LastAIInputs, g_scanTotal);
   ArrayResize(g_LastAIPreds, g_scanTotal);

   AI_InitWeights();

   Print("AI予測エンジン初期化完了(Option2: v1.52結果を再利用)。重みファイル=", AI_WeightFile,
         " 読込=", g_AI_WeightsLoaded ? "OK" : "DEFAULT");

   if(AI_Trainer_Enable)
     {
      // NOTE: v1.52 の SignalLogger は results.csv を出さないため、
      // ここで勝手に学習しない。オンライン学習のみ使う。
      Print("AIトレーナー: 初期学習はスキップ (results.csv なし / オンライン学習のみ)");
     }
  }

//+------------------------------------------------------------------+
//| AI 統合解放                                                       |
//+------------------------------------------------------------------+
void AI_Deinit()
  {
   if(!AI_Enable) return;

   if(AI_Trainer_Enable)
     {
      if(AI_SaveWeights(AI_WeightFile))
         Print("AIトレーナー: 重みを保存しました: ", AI_WeightFile);
     }
  }

//+------------------------------------------------------------------+
//| AI_Input 構築 (再計算なし / v1.52 計算済み結果のみ)                |
//+------------------------------------------------------------------+
bool AI_BuildInput(const int idx, AI_Input &out)
  {
   if(idx < 0 || idx >= g_scanTotal) return false;

   //--- CCompression (g_scan)
   out.compState       = g_scan[idx].state;
   out.compScore       = g_scan[idx].score;
   out.compDelta       = g_scan[idx].delta;
   out.compAge         = g_scan[idx].age;
   out.compATRPctile   = g_scan[idx].atrPctile;
   out.compBBPctile    = g_scan[idx].bbPctile;
   out.compRangePctile = g_scan[idx].rangePctile;
   out.compADX         = g_scan[idx].adxValue; // v1.52 は adxValue
   out.compKCSqueeze   = g_scan[idx].kcSqueeze;
   out.compIsNR        = g_scan[idx].isNR;

   //--- EMA Alignment (銘柄ごとに1回計算済み g_emaAlign)
   int si = idx / g_tfCount;
   if(si >= 0 && si < g_symbolCount && g_emaAlign[si].ready)
     {
      out.emaDir        = g_emaAlign[si].dir;
      out.emaEQS        = g_emaAlign[si].eqs;
      out.emaDepth      = g_emaAlign[si].depthScore;
      out.emaTrendStr   = g_emaAlign[si].trendStrength;
      out.emaAlignScore = g_emaAlign[si].alignmentScore;
      out.emaDiv        = g_emaAlign[si].divergence;
      out.emaZone       = g_emaAlign[si].zoneLabel;
     }
   else
     {
      out.emaDir = 0; out.emaEQS = 0; out.emaDepth = 0;
      out.emaTrendStr = 0; out.emaAlignScore = 0; out.emaDiv = 0;
      out.emaZone = "";
     }

   //--- SuddenMove (急変状態はスキャナーが保持済み)
   if(TimeCurrent() < g_spikeUntil[idx])
     {
      out.smdSpike    = true;
      out.smdRobustZ  = g_spikeZ[idx];
      out.smdATRRatio = g_spikeRatio[idx];
      out.smdEfficiency = 0;
      out.smdBroadRisk = false;
      out.smdRiskMode = "spike";
     }
   else
     {
      out.smdSpike = false; out.smdRobustZ = 0;
      out.smdEfficiency = 0; out.smdATRRatio = 0;
      out.smdBroadRisk = false; out.smdRiskMode = "none";
     }

   //--- Wick (v1.52 は履歴配列のみ。行単位の再計算はしない)
   out.wickDetected = false; out.wickUpper = false;
   out.wickRatio = 0; out.wickMult = 0;

   //--- RelatedPair / Event (再計算なし。Eventのみ軽量取得)
   out.relPct = 0; out.relDir = 0;
   out.relSpikeRel = 0; out.relNRelated = 0;

   EVT_Info evt;
   EVT_GetInfo(g_scan[idx].symbol, PeriodSeconds(g_scan[idx].tf), evt);
   out.evtMinToNext    = evt.minToNext;
   out.evtNextImp      = evt.nextImp;
   out.evtMinToSession = evt.minToSession;
   out.evtScore        = evt.score;
   out.evtMinSinceLast = evt.minSinceLast;

   //--- Ichimoku (計算済み g_ich)
   if(g_ich[idx].ready)
     {
      out.ichPos        = g_ich[idx].pos;
      out.ichThin       = g_ich[idx].thin;
      out.ichBreakDir   = g_ich[idx].breakDir;
      out.ichBreakAgo   = g_ich[idx].breakAgo;
      out.ichRelDir     = g_ich[idx].relDir;
      out.ichBullRoles  = g_ich[idx].bullRoles;
      out.ichBearRoles  = g_ich[idx].bearRoles;
      out.ichTwistAhead = g_ich[idx].twistAhead;
     }
   else
     {
      out.ichPos = 0; out.ichThin = false;
      out.ichBreakDir = 0; out.ichBreakAgo = -1;
      out.ichRelDir = 0; out.ichBullRoles = 0;
      out.ichBearRoles = 0; out.ichTwistAhead = false;
     }

   //--- TD Sequential (計算済み g_td)
   if(g_td[idx].ready)
     {
      out.tdRecent      = g_td[idx].recent;
      out.tdRecentDir   = g_td[idx].recentDir;
      out.tdRecentKind  = g_td[idx].recentKind;
      out.tdRecentAgo   = g_td[idx].recentAgo;
      out.tdLastPerfect = g_td[idx].lastPerfect;
      out.tdCDCount     = g_td[idx].cdCount;
     }
   else
     {
      out.tdRecent = false; out.tdRecentDir = 0;
      out.tdRecentKind = 0; out.tdRecentAgo = -1;
      out.tdLastPerfect = false; out.tdCDCount = 0;
     }

   //--- Wolfe (計算済み g_wlf)
   if(g_wlf[idx].ready)
     {
      out.wlfFound  = g_wlf[idx].found;
      out.wlfState  = g_wlf[idx].state;
      out.wlfDir    = g_wlf[idx].dir;
      out.wlfRR     = g_wlf[idx].rr;
      out.wlfPinBar = g_wlf[idx].pinBar;
      out.wlfEngulf = g_wlf[idx].engulf;
     }
   else
     {
      out.wlfFound = false; out.wlfState = 0;
      out.wlfDir = 0; out.wlfRR = 0;
      out.wlfPinBar = false; out.wlfEngulf = false;
     }

   //--- Volume (計算済み g_vol)
   if(g_vol[idx].ready)
     {
      out.volState     = g_vol[idx].state;
      out.volRatio     = g_vol[idx].ratio;
      out.volSpikeBars = g_vol[idx].spikeBars;
     }
   else
     {
      out.volState = 0; out.volRatio = 0.0; out.volSpikeBars = 0;
     }

   //--- TTM Squeeze (計算済み g_ttm)
   if(g_ttm[idx].ready)
     {
      out.ttmSqueeze  = g_ttm[idx].squeeze;
      out.ttmReleased = g_ttm[idx].released;
      out.ttmMomDir   = g_ttm[idx].momDir;
      out.ttmMomentum = g_ttm[idx].momentum;
     }
   else
     {
      out.ttmSqueeze = false; out.ttmReleased = false;
      out.ttmMomDir = 0; out.ttmMomentum = 0.0;
     }

   //--- RSI Divergence (計算済み g_rsi)
   if(g_rsi[idx].ready)
     {
      out.rsiNow      = g_rsi[idx].rsiNow;
      out.rsiDivDir   = g_rsi[idx].divDir;
      out.rsiRecent   = g_rsi[idx].recent;
      out.rsiStrength = g_rsi[idx].strength;
     }
   else
     {
      out.rsiNow = 50.0; out.rsiDivDir = 0;
      out.rsiRecent = false; out.rsiStrength = 0;
     }

   //--- Supertrend (計算済み g_st)
   if(g_st[idx].ready)
     {
      out.stDir     = g_st[idx].dir;
      out.stFlipped = g_st[idx].flipped;
      out.stBars    = g_st[idx].trendBars;
     }
   else
     {
      out.stDir = 0; out.stFlipped = false; out.stBars = 0;
     }

   //--- Donchian (計算済み g_don)
   if(g_don[idx].ready)
     {
      out.donDir   = g_don[idx].dir;
      out.donPos   = g_don[idx].pos;
      out.donBreak = (g_don[idx].brokeUp || g_don[idx].brokeDown);
     }
   else
     {
      out.donDir = 0; out.donPos = 0; out.donBreak = false;
     }

   //--- Harmonic (計算済み g_harm)
   if(g_harm[idx].ready && g_harm[idx].found)
     {
      out.harmFound   = true;
      out.harmType    = (g_harm[idx].type == HARM_GARTLEY) ? 2 : (g_harm[idx].type == HARM_ABCD ? 1 : 0);
      out.harmDir     = g_harm[idx].direction;
      out.harmName    = g_harm[idx].patternName;
      out.harmPRZDist = 0.0;
      out.harmAge     = 0;

      double curClose = iClose(g_scan[idx].symbol, g_scan[idx].tf, 0);
      double atr = HARM_GetATR(g_scan[idx].symbol, g_scan[idx].tf, 14);
      if(atr > 0.0)
         out.harmPRZDist = (curClose - g_harm[idx].PRZ) / atr;
      out.harmAge = iBarShift(g_scan[idx].symbol, g_scan[idx].tf, g_harm[idx].tD, true);
      if(out.harmAge < 0) out.harmAge = 0;
     }
   else
     {
      out.harmFound = false; out.harmType = 0; out.harmDir = 0;
      out.harmPRZDist = 0.0; out.harmAge = 0; out.harmName = "";
     }

   return true;
  }

//+------------------------------------------------------------------+
//| 行のAI予測更新                                                     |
//+------------------------------------------------------------------+
bool AI_UpdateRow(const int idx, const int kind, string &io_line, color &io_rowClr, string &io_feat)
  {
   if(!AI_Enable) return false;
   if(kind != 0) return false; // 圧縮行のみ。急変・ウォルフ行には付けない
   if(idx < 0 || idx >= g_scanTotal) return false;

   AI_Input aiIn;
   AI_Prediction aiPred;

   if(!AI_BuildInput(idx, aiIn)) return false;
   if(!AI_Predict(aiIn, aiPred)) return false;

   // キャッシュ (詳細パネル用)
   if(ArraySize(g_LastAIInputs) == g_scanTotal)
     {
      g_LastAIInputs[idx] = aiIn;
      g_LastAIPreds[idx]  = aiPred;
     }

      io_line += StringFormat(" AI%s%.0f", AI_DirMark(aiPred.direction), aiPred.confidence);

   if(aiPred.confidence >= AI_HighConfidence && aiPred.direction != 0)
     {
      if(aiPred.direction > 0) io_rowClr = clrDodgerBlue;
      else                     io_rowClr = clrHotPink;
     }

   if(AI_LogToSLG)
     {
      string aiFeat = AI_Feat(aiPred);
      if(StringLen(io_feat) > 0) io_feat += ";";
      io_feat += aiFeat;
     }

   if(AI_AlertOnHighConf && aiPred.confidence >= AI_HighConfidence && aiPred.direction != 0)
     {
      string aiKey = StringFormat("CCOMP_AI_%s_%d_%s",
                     g_scan[idx].symbol, PeriodSeconds(g_scan[idx].tf), AI_ModelVersion);
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
//| 詳細パネル用：今のチャートのAI予測を取得                           |
//+------------------------------------------------------------------+
bool AI_GetCurrentPrediction(AI_Prediction &outPred)
  {
   if(!AI_Enable) return false;
   int detailIdx = -1;
   for(int i = 0; i < g_scanTotal; i++)
     {
      if(g_scan[i].symbol == _Symbol && g_scan[i].tf == (ENUM_TIMEFRAMES)_Period)
        { detailIdx = i; break; }
     }
   if(detailIdx < 0) return false;
   if(!g_scan[detailIdx].ready) return false;

   // 行で計算済みならキャッシュを使う
   if(ArraySize(g_LastAIPreds) == g_scanTotal)
     {
      // キャッシュが古い可能性もあるので、ここでは再予測する
     }

   AI_Input aiIn;
   if(!AI_BuildInput(detailIdx, aiIn)) return false;
   if(!AI_Predict(aiIn, outPred)) return false;

   if(ArraySize(g_LastAIInputs) == g_scanTotal)
     {
      g_LastAIInputs[detailIdx] = aiIn;
      g_LastAIPreds[detailIdx]  = outPred;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| DetailPanel 更新 (今のチャートのみ / 描画はしない)                 |
//| スキャナーの DrawDetailPanel() から AI_GetCurrentPrediction() を  |
//| 呼んで表示する想定。ここではキャッシュ更新だけを行う。            |
//+------------------------------------------------------------------+
void AI_UpdatePanel()
  {
   if(!AI_Enable) return;
   if(g_scanTotal <= 0) return;

   AI_Prediction pred;
   AI_GetCurrentPrediction(pred); // キャッシュ更新のみ
  }

//+------------------------------------------------------------------+
//| 事後評価コールバック                                               |
//+------------------------------------------------------------------+
void AI_OnPostEvaluate(const int idx, int actualDir, double reward, double penalty)
  {
   if(!AI_Trainer_Enable) return;
   if(idx < 0 || idx >= g_scanTotal) return;

   AI_Input aiIn;
   if(!AI_BuildInput(idx, aiIn)) return;

   AI_Trainer_OnlineUpdate(aiIn, actualDir, reward, penalty);
  }
//+------------------------------------------------------------------+
//|                                      TDSequentialEngine.mqh       |
//|  TDシーケンシャル エンジン(簡易版)                                |
//|                                                                    |
//|  ・セットアップ(9本): 終値が「4本前の終値」より連続して高い(低い)  |
//|      上昇側 = 売りセットアップ(S)  → 上昇の疲弊                    |
//|      下降側 = 買いセットアップ(B)  → 下落の疲弊                    |
//|  ・カウントダウン(13本): セットアップ9の完了後に数え始める。       |
//|      終値が「2本前の安値以下(高値以上)」の足を、連続でなくてよいので |
//|      13本数える                                                    |
//|                                                                    |
//|  【位置づけ】                                                     |
//|  TDシーケンシャルは「終値の比較」で、トレンドの疲弊の目安を出す     |
//|  ものであり、圧縮(値幅の縮小)や急変(値幅の拡大)そのものを測る      |
//|  ものではない。このエンジンは圧縮・急変を置き換えるのではなく、     |
//|  「圧縮解除や急変が、トレンドの疲弊の直後に起きたか」を確認する      |
//|  補助的な情報として使う。効果があるかは検証ログで確かめる前提。      |
//|                                                                    |
//|  【簡易版の範囲】                                                 |
//|  ・プライスフリップ、パーフェクション、13本目の資格条件は実装。      |
//|  ・TDST(サポート/レジスタンス)による取消や、複雑なリサイクル規則は  |
//|    実装していない。逆向きのセットアップ9が完了したら、カウントダウン |
//|    を取り消して新しい向きで数え直す。                              |
//|                                                                    |
//|  毎回、過去 TDS_Lookback 本から状態を再現して求める(ステートレス)。 |
//|  チャート切替でインジケーターが読み込み直されても結果が変わらない。 |
//+------------------------------------------------------------------+
#property strict

input group "=== TDシーケンシャル ==="
input bool TDS_Enable           = true;  // TDシーケンシャルを計算する
input int  TDS_Lookback         = 300;   // 状態を再現する過去の本数
input int  TDS_RecentBars       = 3;     // 「直近」とみなす本数(9や13の完了から何本以内か)
input bool TDS_RequirePriceFlip = true;  // セットアップの開始にプライスフリップを要求する(標準ルール)
input bool TDS_ShowInList       = true;  // 一覧にTDの表示を付ける
input int  TDS_ShowMinSetup     = 7;     // 一覧に表示する、進行中セットアップの最小カウント
input int  TDS_ShowMinCountdown = 10;    // 一覧に表示する、進行中カウントダウンの最小カウント
input bool TDS_AlertOnCombo     = true;  // 圧縮解除/急変とTD完了が重なった時に通知する

struct TDS_Result
  {
   bool ready;
   int  setupDir;      // 進行中のセットアップの向き: +1=上昇側(S) -1=下降側(B) 0=なし
   int  setupCount;    // 進行中のセットアップの本数(1〜8。9で完了するとリセットされる)
   int  cdDir;         // 進行中のカウントダウンの向き
   int  cdCount;       // 進行中のカウントダウンの数(0〜12)
   int  lastSetupDir;  // 直近に完了したセットアップ(9)の向き
   int  lastSetupAgo;  // その完了から何本前か(0=最新の確定足で完了。なし=-1)
   bool lastPerfect;   // そのセットアップは「パーフェクト」か
   int  lastCdDir;     // 直近に完了したカウントダウン(13)の向き
   int  lastCdAgo;     // その完了から何本前か(なし=-1)
   bool recent;        // TDS_RecentBars以内に9または13が完了している
   int  recentDir;     // その向き
   int  recentAgo;     // 何本前か
   int  recentKind;    // 9=セットアップ / 13=カウントダウン
  };

//+------------------------------------------------------------------+
//| 計算(最後の確定足の時点の状態を求める)                            |
//+------------------------------------------------------------------+
bool TDS_Compute(const string symbol, const ENUM_TIMEFRAMES tf, TDS_Result &r)
  {
   r.ready        = false;
   r.setupDir     = 0;
   r.setupCount   = 0;
   r.cdDir        = 0;
   r.cdCount      = 0;
   r.lastSetupDir = 0;
   r.lastSetupAgo = -1;
   r.lastPerfect  = false;
   r.lastCdDir    = 0;
   r.lastCdAgo    = -1;
   r.recent       = false;
   r.recentDir    = 0;
   r.recentAgo    = -1;
   r.recentKind   = 0;

   int N = MathMax(30, TDS_Lookback) + 8;
   double c[], h[], l[];
   ArraySetAsSeries(c, true);
   ArraySetAsSeries(h, true);
   ArraySetAsSeries(l, true);
   int g1 = CopyClose(symbol, tf, 1, N, c);
   int g2 = CopyHigh(symbol, tf, 1, N, h);
   int g3 = CopyLow(symbol, tf, 1, N, l);
   int got = MathMin(g1, MathMin(g2, g3));
   if(got < 30)
      return false;

   int    setupDir = 0, setupCount = 0;
   int    cdDir = 0, cdCount = 0;
   double cd8Close = 0.0;
   int    lastSetupDir = 0, lastSetupAgo = -1;
   bool   lastPerf = false;
   int    lastCdDir = 0, lastCdAgo = -1;

   //--- 古い足(添字が大きい)から新しい足(添字0)へ向かって状態を再現する ---
   for(int k = got - 6; k >= 0; k--)
     {
      bool buyCond  = (c[k] < c[k + 4]);
      bool sellCond = (c[k] > c[k + 4]);
      bool buyFlip  = buyCond  && (c[k + 1] > c[k + 5]);   // 直前の足は逆向きだった(プライスフリップ)
      bool sellFlip = sellCond && (c[k + 1] < c[k + 5]);

      //--- セットアップ ---
      if(setupDir == -1)
        {
         if(buyCond) setupCount++;
         else { setupDir = 0; setupCount = 0; }
        }
      else if(setupDir == 1)
        {
         if(sellCond) setupCount++;
         else { setupDir = 0; setupCount = 0; }
        }

      if(setupDir == 0)
        {
         if(TDS_RequirePriceFlip)
           {
            if(buyFlip)       { setupDir = -1; setupCount = 1; }
            else if(sellFlip) { setupDir = 1;  setupCount = 1; }
           }
         else
           {
            if(buyCond)       { setupDir = -1; setupCount = 1; }
            else if(sellCond) { setupDir = 1;  setupCount = 1; }
           }
        }

      bool completedNow = false;
      int  completedDir = 0;
      if(setupCount == 9)
        {
         completedNow = true;
         completedDir = setupDir;

         // パーフェクト: 8本目または9本目の安値(高値)が、6本目・7本目より低い(高い)
         bool perf;
         if(setupDir == -1)
            perf = (l[k + 1] <= l[k + 3] && l[k + 1] <= l[k + 2]) || (l[k] <= l[k + 3] && l[k] <= l[k + 2]);
         else
            perf = (h[k + 1] >= h[k + 3] && h[k + 1] >= h[k + 2]) || (h[k] >= h[k + 3] && h[k] >= h[k + 2]);

         lastSetupDir = setupDir;
         lastSetupAgo = k;      // 添字kは「最新の確定足から何本前か」にそのまま対応する
         lastPerf     = perf;

         setupDir = 0;          // 9で完了。次のセットアップは新しいフリップから始まる
         setupCount = 0;
        }

      //--- カウントダウン ---
      if(completedNow && cdDir != completedDir)
        {
         // 逆向きのセットアップが完了 → 以前のカウントダウンを取り消し、新しい向きで数え直す
         cdDir = completedDir;
         cdCount = 0;
         cd8Close = 0.0;
        }

      if(cdDir != 0)
        {
         bool q = (cdDir == -1) ? (c[k] <= l[k + 2]) : (c[k] >= h[k + 2]);
         if(q)
           {
            bool ok = true;
            if(cdCount == 12)   // 13本目の資格条件: 8本目のカウントダウン足の終値との比較
               ok = (cdDir == -1) ? (l[k] <= cd8Close) : (h[k] >= cd8Close);
            if(ok)
              {
               cdCount++;
               if(cdCount == 8)
                  cd8Close = c[k];
               if(cdCount == 13)
                 {
                  lastCdDir = cdDir;
                  lastCdAgo = k;
                  cdDir = 0;
                  cdCount = 0;
                  cd8Close = 0.0;
                 }
              }
           }
        }
     }

   r.setupDir     = setupDir;
   r.setupCount   = setupCount;
   r.cdDir        = cdDir;
   r.cdCount      = cdCount;
   r.lastSetupDir = lastSetupDir;
   r.lastSetupAgo = lastSetupAgo;
   r.lastPerfect  = lastPerf;
   r.lastCdDir    = lastCdDir;
   r.lastCdAgo    = lastCdAgo;

   //--- 「直近」の完了(13と9が両方ある場合は新しい方。同じなら13を優先) ---
   bool sRec = (lastSetupAgo >= 0 && lastSetupAgo < TDS_RecentBars);
   bool cRec = (lastCdAgo >= 0 && lastCdAgo < TDS_RecentBars);
   if(cRec && (!sRec || lastCdAgo <= lastSetupAgo))
     {
      r.recent = true;
      r.recentDir = lastCdDir;
      r.recentAgo = lastCdAgo;
      r.recentKind = 13;
     }
   else if(sRec)
     {
      r.recent = true;
      r.recentDir = lastSetupDir;
      r.recentAgo = lastSetupAgo;
      r.recentKind = 9;
     }

   r.ready = true;
   return true;
  }

//+------------------------------------------------------------------+
//| 表示・判定用                                                       |
//+------------------------------------------------------------------+
string TDS_DirChar(const int dir)
  {
   if(dir > 0) return "S";
   if(dir < 0) return "B";
   return "-";
  }

//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string TDS_Text(const TDS_Result &r)
  {
   if(!r.ready)
      return "";
   string t = "";
   if(r.recent)
     {
      t += StringFormat("%s%d完了", TDS_DirChar(r.recentDir), r.recentKind);
      if(r.recentAgo > 0)
         t += StringFormat("(%d本前)", r.recentAgo);
     }
   if(r.setupCount >= TDS_ShowMinSetup)
     {
      if(StringLen(t) > 0) t += " ";
      t += StringFormat("%s%d/9", TDS_DirChar(r.setupDir), r.setupCount);
     }
   if(r.cdCount >= TDS_ShowMinCountdown)
     {
      if(StringLen(t) > 0) t += " ";
      t += StringFormat("CD:%s%d/13", TDS_DirChar(r.cdDir), r.cdCount);
     }
   if(StringLen(t) == 0)
      return "";
   return "  [TD " + t + "]";
  }

//--- 反転整合: 直近に完了したTDの向きと、逆方向への急変か
//---   上昇の疲弊(S)が完了 → 下への急変 / 下落の疲弊(B)が完了 → 上への急変
bool TDS_IsReversalAligned(const TDS_Result &r, const bool spikeUp)
  {
   if(!r.ready || !r.recent)
      return false;
   if(r.recentDir > 0 && !spikeUp) return true;
   if(r.recentDir < 0 && spikeUp)  return true;
   return false;
  }

//--- 検証ログ用の特徴量(ASCIIのみ。カンマは使わない)
string TDS_Feat(const TDS_Result &r)
  {
   if(!r.ready)
      return "td_ready=0";
   return StringFormat("td_set=%s%d;td_cd=%s%d;td_recent=%d;td_kind=%d;td_dir=%d;td_ago=%d;td_perf=%d",
                       TDS_DirChar(r.setupDir), r.setupCount, TDS_DirChar(r.cdDir), r.cdCount,
                       r.recent ? 1 : 0, r.recentKind, r.recentDir, r.recentAgo, r.lastPerfect ? 1 : 0);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                              SignalLogger.mqh     |
//|  結果記録エンジン(検証用)                                          |
//|                                                                    |
//|  シグナル(TRANSITION・急変など)と、基準(対照)となる足を events.csv に |
//|  記録し、その後 N本(その時間足の本数)経過した時点で、実際にどれだけ    |
//|  動いたかをATR倍で計算して results.csv に追記する。                 |
//|  集計とテキストレポートは、基準との比較を中心に作る。               |
//|                                                                    |
//|  保存先: MQL5/Files/<SLG_Folder>/CCOMP_events.csv                 |
//|          MQL5/Files/<SLG_Folder>/CCOMP_results.csv                |
//|          MQL5/Files/<SLG_Folder>/CCOMP_report.txt                 |
//|                                                                    |
//|  【重要】MQL5のプログラムは MQL5/Files の外には書き込めない。      |
//|  既定の保存先 "Verification log" を                               |
//|  MQL5/Indicators/claude.ai/Verification log に置くには、           |
//|  MQL5/Files/Verification log からのジャンクション(mklink /J)を     |
//|  先に作っておく(手順は README を参照)。                           |
//|                                                                    |
//|  評価は1分足データで行うため、チャートを閉じていても次回起動時に    |
//|  未評価の分をまとめて評価する(再起動・チャート切替に強い)。        |
//|                                                                    |
//|  【集計の考え方】                                                 |
//|  ・「動いた」の基準は、評価本数に応じて補正する。ATRの何倍動いたかは、 |
//|    本数が長いほど大きくなる(約√本数)ので、固定の1ATRだと長い本数で    |
//|    何もなくても大半が「動いた」になってしまうため。                 |
//|  ・集計に入れるのは、全ての評価本数が揃ったイベントだけ。             |
//|    (本数ごとに対象のイベントが違うと、本数の間で比べられない)        |
//|  ・イベントは互いに独立ではない。評価期間(評価本数×時間足)が重なる    |
//|    イベントは、同じ値動きを見ているので、通貨ペアが違っても1つの塊と    |
//|    数える。この塊の数を「実効件数」とし、信頼区間と検定に使う。        |
//|    (最初のイベントから評価期間の長さの窓を作り、窓に入るものを同じ塊に) |
//|  ・急変(SPIKE系)は、同じ銘柄・時間足で SLG_EpisodeBars 本以内に続けて   |
//|    記録されたものを、1つの急変として数える(続く急変の重複の掃除)。      |
//|  ・比較の相手(基準)は、シグナルの種類ごとに決める。                  |
//|    TRANSITION系 : BASE_RISE → BASE_COMP → BASE                    |
//|    SPIKE系      : BASE_COMP → BASE                                |
//|    その他       : BASE                                            |
//|    (最初に実効件数が足りるものを使う)                              |
//|                                                                    |
//|  【注意】スキャナーは1つのチャートだけで動かしてください。         |
//|  複数チャートで同時に動かすと、評価結果が重複して記録されます。    |
//+------------------------------------------------------------------+
#property strict

input group "=== 結果記録(検証ログ) ==="
input bool   SLG_Enable          = true;            // 起動時にログを記録する(チャート上のボタンで随時切替可)
input string SLG_Horizons        = "3,6,12";        // 評価する本数(その時間足の本数、カンマ区切り)
input double SLG_HitATR          = 1.0;             // 「動いた」とみなす最大変動幅(ATR倍)。評価本数が SLG_HitRefBars の時の値
input int    SLG_HitRefBars      = 3;               // 上の基準値を適用する評価本数。他の本数では √(本数/この値) 倍に補正する
input string SLG_Folder          = "Verification log"; // MQL5/Files内の保存フォルダ(ジャンクション経由でclaude.ai内に置く)
input int    SLG_EvalIntervalSec = 60;              // 未評価分のチェック間隔(秒)
input double SLG_BaseRate        = 0.01;            // 基準の記録(BASE): すべての確定足から無作為に抜き出す割合
input double SLG_BaseCompRate    = 0.05;            // 基準の記録(BASE_COMP): 圧縮中の確定足から抜き出す割合
input double SLG_BaseRiseRate    = 0.30;            // 基準の記録(BASE_RISE): 「前の足が強い圧縮で、ATR/BB幅が上昇し、Scoreは下がっていない」足から抜き出す割合
input int    SLG_MinN            = 30;              // レポートで「判定できる」とみなす最小の実効件数(これ未満は参考値)
input int    SLG_EpisodeBars     = 4;               // 急変(SPIKE系)を「続き」とみなす間隔(本数)。同じ銘柄・時間足でこの本数以内に続けて記録されたものは1つと数える
input int    SLG_ReportIntervalMin = 30;            // レポートの自動出力間隔(分)。0=自動では出さない(ボタンで出力)

#define SLG_EV_HEADER "id,type,symbol,tf_sec,time,price,atr,features"
#define SLG_RS_HEADER "id,type,symbol,tf_sec,event_time,price,atr,horizon,close_atr,max_up_atr,max_down_atr,max_exc_atr,features"

//--- イベント(メモリ上)
string   SLG_evId[];
string   SLG_evType[];
string   SLG_evSym[];
int      SLG_evTf[];
datetime SLG_evTime[];
double   SLG_evPrice[];
double   SLG_evAtr[];
string   SLG_evFeat[];

//--- 文字列→整数の高速な対応表(ハッシュ)
//--- 評価済み("id|horizon")と、記録済みのイベントIDの検索に使う
string   SLG_dnKeys[];   int SLG_dnVals[];   int SLG_dnCnt = 0;
string   SLG_idKeys[];   int SLG_idVals[];   int SLG_idCnt = 0;
string   SLG_dpKeys[];   int SLG_dpVals[];   int SLG_dpCnt = 0;   // 集計から除くイベントID(続く急変の2件目以降)

//--- 集計(種類 × 時間足 × 評価本数)。SLG_stTf=0 は「全時間足」
string   SLG_stType[];
int      SLG_stTf[];
int      SLG_stH[];
int      SLG_stN[];        // 件数
int      SLG_stEff[];      // 実効件数(同じ時間足の同じ足に出たイベントを1つとして数える)
int      SLG_stHit[];      // 最大変動が「動いた」の基準(本数で補正)以上だった件数
int      SLG_stHit2[];     // 最大変動が2ATR以上だった件数(固定)
int      SLG_stHit3[];     // 最大変動が3ATR以上だった件数(固定)
double   SLG_stSum[];      // 最大変動の合計(ATR倍)
double   SLG_stNorm[];     // 最大変動÷√本数 の合計(本数で補正した値幅)
int      SLG_stUp[];       // 上方向に基準以上動いた件数
int      SLG_stDn[];       // 下方向に基準以上動いた件数
int      SLG_stDirN[];     // 方向つきシグナル(features に sig=up/down があるもの)の件数
int      SLG_stFav[];      // そのうち、期待方向に基準以上動いた件数
int      SLG_stAdv[];      // そのうち、逆方向に基準以上動いた件数
double   SLG_stFavSum[];   // 期待方向への最大変動の合計(ATR倍)
datetime SLG_stWinEnd[];   // 実効件数を数える時間窓の終了時刻(この時刻になるまでのイベントは同じ塊)
string   SLG_statLines[];

int      SLG_pending = 0;  // 評価待ち(全本数が揃っていない)のイベント数
int      SLG_horizons[];
datetime SLG_lastEval = 0;
bool     SLG_ready = false;   // 初期化済み(過去ログの読込が済んでいる)
bool     SLG_on    = false;   // ログ記録のON/OFF(実行中に切り替え可能)

//+------------------------------------------------------------------+
string SLG_EventsPath()  { return SLG_Folder + "\\CCOMP_events.csv"; }
string SLG_ResultsPath() { return SLG_Folder + "\\CCOMP_results.csv"; }
string SLG_ReportPath()  { return SLG_Folder + "\\CCOMP_report.txt"; }

//+------------------------------------------------------------------+
//| 1行追記(ファイルが空ならヘッダーを先に書く)                       |
//+------------------------------------------------------------------+
bool SLG_AppendLine(const string path, const string line, const string header)
  {
   int h = FileOpen(path, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      PrintFormat("SLG_AppendLine: ファイルを開けません %s (error=%d)", path, GetLastError());
      return false;
     }
   if(FileSize(h) == 0)
      FileWriteString(h, header + "\r\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, line + "\r\n");
   FileClose(h);
   return true;
  }

//+------------------------------------------------------------------+
//| ハッシュによる 文字列→整数 の対応表(線形探索だと件数が増えると遅いため)|
//+------------------------------------------------------------------+
uint SLG_HashStr(const string s)
  {
   uint h = 2166136261;
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
     {
      h ^= (uint)StringGetCharacter(s, i);
      h *= 16777619;
     }
   return h;
  }

void SLG_MapInsertRaw(string &keys[], int &vals[], const string key, const int val)
  {
   int cap = ArraySize(keys);
   int mask = cap - 1;
   int i = (int)(SLG_HashStr(key) & (uint)mask);
   while(keys[i] != "")
     {
      if(keys[i] == key) { vals[i] = val; return; }
      i = (i + 1) & mask;
     }
   keys[i] = key;
   vals[i] = val;
  }

void SLG_MapGrow(string &keys[], int &vals[])
  {
   int ocap = ArraySize(keys);
   string ok[];
   int    ov[];
   ArrayResize(ok, ocap);
   ArrayResize(ov, ocap);
   for(int i = 0; i < ocap; i++) { ok[i] = keys[i]; ov[i] = vals[i]; }

   int ncap = (ocap < 1024) ? 1024 : ocap * 2;   // 常に2のべき乗
   ArrayResize(keys, ncap);
   ArrayResize(vals, ncap);
   for(int i = 0; i < ncap; i++) { keys[i] = ""; vals[i] = 0; }
   for(int i = 0; i < ocap; i++)
      if(ok[i] != "")
         SLG_MapInsertRaw(keys, vals, ok[i], ov[i]);
  }

//--- キーの位置(なければ -1)
int SLG_MapFind(const string &keys[], const string key)
  {
   int cap = ArraySize(keys);
   if(cap == 0)
      return -1;
   int mask = cap - 1;
   int i = (int)(SLG_HashStr(key) & (uint)mask);
   for(int step = 0; step < cap; step++)
     {
      if(keys[i] == "")  return -1;
      if(keys[i] == key) return i;
      i = (i + 1) & mask;
     }
   return -1;
  }

void SLG_MapPut(string &keys[], int &vals[], int &cnt, const string key, const int val)
  {
   int s = SLG_MapFind(keys, key);
   if(s >= 0)
     {
      vals[s] = val;
      return;
     }
   if(ArraySize(keys) == 0 || (cnt + 1) * 2 > ArraySize(keys))
      SLG_MapGrow(keys, vals);
   SLG_MapInsertRaw(keys, vals, key, val);
   cnt++;
  }

int SLG_MapGet(const string &keys[], const int &vals[], const string key, const int def)
  {
   int s = SLG_MapFind(keys, key);
   return (s >= 0) ? vals[s] : def;
  }

//+------------------------------------------------------------------+
bool SLG_EventExists(const string id)  { return (SLG_MapFind(SLG_idKeys, id) >= 0); }
void SLG_AddEventId(const string id)   { SLG_MapPut(SLG_idKeys, SLG_idVals, SLG_idCnt, id, 1); }
bool SLG_IsDone(const string key)      { return (SLG_MapFind(SLG_dnKeys, key) >= 0); }
void SLG_AddDone(const string key)     { SLG_MapPut(SLG_dnKeys, SLG_dnVals, SLG_dnCnt, key, 1); }

//+------------------------------------------------------------------+
//| 時間足の表示・「動いた」の基準                                     |
//+------------------------------------------------------------------+
string SLG_TfText(const int tfSec)
  {
   switch(tfSec)
     {
      case 0:      return "全TF";
      case 60:     return "M1";
      case 300:    return "M5";
      case 900:    return "M15";
      case 1800:   return "M30";
      case 3600:   return "H1";
      case 14400:  return "H4";
      case 86400:  return "D1";
     }
   return IntegerToString(tfSec) + "s";
  }

//--- 評価本数Hでの「動いた」の基準(ATR倍)。値幅は約√本数で大きくなるので補正する
double SLG_Thr(const int H)
  {
   return SLG_HitATR * MathSqrt((double)H / (double)MathMax(1, SLG_HitRefBars));
  }

//+------------------------------------------------------------------+
//| 集計(種類 × 時間足 × 評価本数)                                    |
//+------------------------------------------------------------------+
int SLG_FindStat(const string type, const int tfSec, const int H)
  {
   int n = ArraySize(SLG_stType);
   for(int i = 0; i < n; i++)
      if(SLG_stType[i] == type && SLG_stTf[i] == tfSec && SLG_stH[i] == H)
         return i;
   return -1;
  }

int SLG_StatIndex(const string type, const int tfSec, const int H)
  {
   int f = SLG_FindStat(type, tfSec, H);
   if(f >= 0)
      return f;
   int n = ArraySize(SLG_stType);
   ArrayResize(SLG_stType, n + 1);
   ArrayResize(SLG_stTf,   n + 1);
   ArrayResize(SLG_stH,    n + 1);
   ArrayResize(SLG_stN,    n + 1);
   ArrayResize(SLG_stEff,  n + 1);
   ArrayResize(SLG_stHit,  n + 1);
   ArrayResize(SLG_stHit2, n + 1);
   ArrayResize(SLG_stHit3, n + 1);
   ArrayResize(SLG_stSum,  n + 1);
   ArrayResize(SLG_stNorm, n + 1);
   ArrayResize(SLG_stUp,   n + 1);
   ArrayResize(SLG_stDn,   n + 1);
   ArrayResize(SLG_stDirN, n + 1);
   ArrayResize(SLG_stFav,  n + 1);
   ArrayResize(SLG_stAdv,  n + 1);
   ArrayResize(SLG_stFavSum, n + 1);
   ArrayResize(SLG_stWinEnd, n + 1);
   SLG_stType[n] = type;
   SLG_stTf[n]   = tfSec;
   SLG_stH[n]    = H;
   SLG_stN[n] = 0;  SLG_stEff[n] = 0;  SLG_stHit[n] = 0;  SLG_stHit2[n] = 0;  SLG_stHit3[n] = 0;
   SLG_stSum[n] = 0.0;  SLG_stNorm[n] = 0.0;
   SLG_stUp[n] = 0;  SLG_stDn[n] = 0;
   SLG_stDirN[n] = 0;  SLG_stFav[n] = 0;  SLG_stAdv[n] = 0;  SLG_stFavSum[n] = 0.0;
   SLG_stWinEnd[n] = 0;
   return n;
  }

void SLG_StatAdd(const int si, const int H, const double maxExc, const double upAtr, const double dnAtr,
                 const int sigDir, const bool newCluster)
  {
   double thr = SLG_Thr(H);
   SLG_stN[si]++;
   if(newCluster)         SLG_stEff[si]++;
   if(maxExc >= thr)      SLG_stHit[si]++;
   if(maxExc >= 2.0)      SLG_stHit2[si]++;
   if(maxExc >= 3.0)      SLG_stHit3[si]++;
   SLG_stSum[si]  += maxExc;
   SLG_stNorm[si] += maxExc / MathSqrt((double)MathMax(1, H));
   if(upAtr >= thr)       SLG_stUp[si]++;
   if(dnAtr >= thr)       SLG_stDn[si]++;
   if(sigDir != 0)
     {
      double fav = (sigDir > 0) ? upAtr : dnAtr;
      double adv = (sigDir > 0) ? dnAtr : upAtr;
      SLG_stDirN[si]++;
      if(fav >= thr) SLG_stFav[si]++;
      if(adv >= thr) SLG_stAdv[si]++;
      SLG_stFavSum[si] += fav;
     }
  }

//+------------------------------------------------------------------+
//| 基準(対照)との比較                                                |
//|  BASE      : すべての確定足から無作為に抜き出した足                |
//|  BASE_COMP : 圧縮中(COMPRESSION以上)の確定足から抜き出した足        |
//|  BASE_RISE : 前の足が強い圧縮で、ATR/BB幅が上昇し、Scoreは下がって   |
//|              いない足。TRANSITIONの条件のうち「Scoreが下がる」だけが  |
//|              違う対照。「ボラが戻り始めたから動く」という当たり前の    |
//|              性質と、解除の検出の効果を区別するためのもの。          |
//+------------------------------------------------------------------+
bool SLG_IsBaseType(const string t)
  {
   return (StringFind(t, "BASE") == 0);
  }

//--- 比較の相手の候補(優先順)。戻り値は候補数
int SLG_BaseChain(const string type, string &chain[])
  {
   ArrayResize(chain, 3);
   if(StringFind(type, "TRANSITION") == 0)
     {
      chain[0] = "BASE_RISE"; chain[1] = "BASE_COMP"; chain[2] = "BASE";
      return 3;
     }
   if(StringFind(type, "SPIKE") == 0)
     {
      chain[0] = "BASE_COMP"; chain[1] = "BASE";
      return 2;
     }
   chain[0] = "BASE";
   return 1;
  }

//--- 比較に使う基準を選ぶ。候補のうち、最初に実効件数が足りるものを使う。
//--- どれも足りなければ、実効件数が最も多いものを使う。
//--- pMax: 基準で「最大変動が基準以上」の割合 / pNeutral: 「片方向に基準以上」の割合(上と下の平均)
bool SLG_GetBase(const string type, const int tfSec, const int H,
                 double &pMax, double &pNeutral, int &nBase, int &nEffBase, string &baseName)
  {
   string chain[];
   int nc = SLG_BaseChain(type, chain);
   int best = -1;
   for(int c = 0; c < nc; c++)
     {
      int bi = SLG_FindStat(chain[c], tfSec, H);
      if(bi < 0 || SLG_stN[bi] <= 0)
         continue;
      if(SLG_stEff[bi] >= SLG_MinN)
        {
         best = bi;
         break;
        }
      if(best < 0 || SLG_stEff[bi] > SLG_stEff[best])
         best = bi;
     }
   if(best < 0)
      return false;
   nBase = SLG_stN[best];
   nEffBase = MathMax(1, SLG_stEff[best]);
   baseName = SLG_stType[best];
   pMax = (double)SLG_stHit[best] / nBase;
   pNeutral = (double)(SLG_stUp[best] + SLG_stDn[best]) / (2.0 * nBase);
   return true;
  }

//+------------------------------------------------------------------+
//| 統計計算                                                           |
//+------------------------------------------------------------------+
double SLG_Erf(const double xin)
  {
   double sgn = (xin < 0.0) ? -1.0 : 1.0;
   double x = MathAbs(xin);
   double t = 1.0 / (1.0 + 0.3275911 * x);
   double y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * MathExp(-x * x);
   return sgn * y;
  }

double SLG_NormCdf(const double z)
  {
   return 0.5 * (1.0 + SLG_Erf(z / 1.4142135623730951));
  }

//--- ウィルソンの95%信頼区間
void SLG_Wilson(const double k, const double n, double &lo, double &hi)
  {
   if(n <= 0.0) { lo = 0.0; hi = 0.0; return; }
   double z = 1.96;
   double p = k / n;
   double d = 1.0 + z * z / n;
   double c = p + z * z / (2.0 * n);
   double a = z * MathSqrt(MathMax(0.0, p * (1.0 - p) / n + z * z / (4.0 * n * n)));
   lo = (c - a) / d;
   hi = (c + a) / d;
  }

//--- 2つの割合の差の検定(両側)。diff = k1/n1 - k2/n2
double SLG_PValue(const double k1, const double n1, const double k2, const double n2, double &diff)
  {
   diff = 0.0;
   if(n1 <= 0.0 || n2 <= 0.0)
      return 1.0;
   double p1 = k1 / n1;
   double p2 = k2 / n2;
   diff = p1 - p2;
   double pp = (k1 + k2) / (n1 + n2);
   double se = MathSqrt(MathMax(0.0, pp * (1.0 - pp) * (1.0 / n1 + 1.0 / n2)));
   if(se <= 0.0)
      return 1.0;
   return 2.0 * (1.0 - SLG_NormCdf(MathAbs(diff / se)));
  }

//--- 判定。シグナル側と基準側の「両方」の実効件数が足りている時だけ判定する
string SLG_Verdict(const double nEffSig, const double nEffBase, const double diff, const double p)
  {
   if(nEffSig < SLG_MinN)
      return StringFormat("n不足(シグナルの実効件数%.0f<%d)", nEffSig, SLG_MinN);
   if(nEffBase < SLG_MinN)
      return StringFormat("n不足(基準の実効件数%.0f<%d)", nEffBase, SLG_MinN);
   if(p < 0.05)
      return (diff > 0.0) ? "基準より高い(偶然の可能性あり・要追試)" : "基準より低い";
   return "基準との差は有意でない";
  }

//--- 1つの集計(種類×時間足×本数)を、レポートの1行にする
//--- 信頼区間と検定は「実効件数」で計算する(同じ足に複数の通貨ペアで出たものを1つと数える)
string SLG_FmtLine(const int si, int &cmp, int &sigHigh, int &sigLow)
  {
   string type = SLG_stType[si];
   int tf = SLG_stTf[si];
   int H  = SLG_stH[si];
   int n  = SLG_stN[si];
   double thr = SLG_Thr(H);
   double nEff = (double)MathMax(1, SLG_stEff[si]);
   if(n <= 0)
      return StringFormat("%-15s %-5s H=%-3d (データなし)", type, SLG_TfText(tf), H);

   double scale = nEff / (double)n;   // 実効件数/件数(1以下)
   string head = StringFormat("%-15s %-5s H=%-3d n=%-4d(実効%.0f) ", type, SLG_TfText(tf), H, n, nEff);
   string extra = StringFormat("≥2ATR %.0f%% ≥3ATR %.0f%%  平均最大変動%.2fATR(÷√本数 %.2f)",
                               (double)SLG_stHit2[si] / n * 100.0, (double)SLG_stHit3[si] / n * 100.0,
                               SLG_stSum[si] / n, SLG_stNorm[si] / n);

   //--- 基準そのもの ---
   if(SLG_IsBaseType(type))
     {
      double lo, hi;
      SLG_Wilson(SLG_stHit[si] * scale, nEff, lo, hi);
      return head + StringFormat("動いた(≥%.2fATR)%.1f%% [95%%CI %.0f-%.0f]  上方向%.1f%% 下方向%.1f%%  %s",
                                 thr, (double)SLG_stHit[si] / n * 100.0, lo * 100.0, hi * 100.0,
                                 (double)SLG_stUp[si] / n * 100.0, (double)SLG_stDn[si] / n * 100.0, extra);
     }

   double pMaxB, pNeuB;
   int    nB, nEffB;
   string bName;
   bool hasBase = SLG_GetBase(type, tf, H, pMaxB, pNeuB, nB, nEffB, bName);

   //--- 方向つき: 順方向に動いた割合を、基準の「片方向」と比べる ---
   if(SLG_stDirN[si] > 0)
     {
      int nd = SLG_stDirN[si];
      double ndEff = MathMax(1.0, nEff * (double)nd / (double)n);
      double sc = ndEff / (double)nd;
      double pf = (double)SLG_stFav[si] / nd;
      double pa = (double)SLG_stAdv[si] / nd;
      double lo, hi;
      SLG_Wilson(SLG_stFav[si] * sc, ndEff, lo, hi);
      string s = StringFormat("%-15s %-5s H=%-3d n=%-4d(実効%.0f) 順方向(≥%.2fATR)%.1f%% [95%%CI %.0f-%.0f]  逆行%.1f%%  順方向-逆行 %+.1fpt  平均順方向%.2fATR",
                              type, SLG_TfText(tf), H, nd, ndEff, thr, pf * 100.0, lo * 100.0, hi * 100.0,
                              pa * 100.0, (pf - pa) * 100.0, SLG_stFavSum[si] / nd);
      if(!hasBase)
         return s + "  基準なし";
      double diff;
      double p = SLG_PValue(SLG_stFav[si] * sc, ndEff, pNeuB * nEffB, (double)nEffB, diff);
      s += StringFormat("  | 基準(%s n=%d 実効%d)の片方向%.1f%% → 差%+.1fpt p=%.3f  %s",
                        bName, nB, nEffB, pNeuB * 100.0, diff * 100.0, p, SLG_Verdict(ndEff, nEffB, diff, p));
      if(ndEff >= SLG_MinN && nEffB >= SLG_MinN)
        {
         cmp++;
         if(p < 0.05 && diff > 0.0) sigHigh++;
         if(p < 0.05 && diff < 0.0) sigLow++;
        }
      return s;
     }

   //--- 方向なし: 最大変動(上下どちらでも)が基準以上だった割合を、基準と比べる ---
   double pHit = (double)SLG_stHit[si] / n;
   double lo, hi;
   SLG_Wilson(SLG_stHit[si] * scale, nEff, lo, hi);
   string s = head + StringFormat("動いた(≥%.2fATR)%.1f%% [95%%CI %.0f-%.0f]  %s",
                                  thr, pHit * 100.0, lo * 100.0, hi * 100.0, extra);
   if(!hasBase)
      return s + "  基準なし";
   double diff;
   double p = SLG_PValue(SLG_stHit[si] * scale, nEff, pMaxB * nEffB, (double)nEffB, diff);
   s += StringFormat("  | 基準(%s n=%d 実効%d) %.1f%% → 差%+.1fpt p=%.3f  %s",
                     bName, nB, nEffB, pMaxB * 100.0, diff * 100.0, p, SLG_Verdict(nEff, nEffB, diff, p));
   if(nEff >= SLG_MinN && nEffB >= SLG_MinN)
     {
      cmp++;
      if(p < 0.05 && diff > 0.0) sigHigh++;
      if(p < 0.05 && diff < 0.0) sigLow++;
     }
   return s;
  }

//+------------------------------------------------------------------+
//| 画面の検証パネル用の行(全時間足の集計のみ)                        |
//+------------------------------------------------------------------+
void SLG_BuildStatLines()
  {
   int n = ArraySize(SLG_stType);
   ArrayResize(SLG_statLines, 0);
   for(int i = 0; i < n; i++)
     {
      if(SLG_stTf[i] != 0 || SLG_stN[i] <= 0)
         continue;
      string type = SLG_stType[i];
      int H = SLG_stH[i];
      double thr = SLG_Thr(H);
      double nEff = (double)MathMax(1, SLG_stEff[i]);
      string line;

      double pMaxB, pNeuB;
      int    nB, nEffB;
      string bName;
      bool hasBase = (!SLG_IsBaseType(type)) && SLG_GetBase(type, 0, H, pMaxB, pNeuB, nB, nEffB, bName);

      if(SLG_stDirN[i] > 0)
        {
         double fav = (double)SLG_stFav[i] / SLG_stDirN[i];
         double adv = (double)SLG_stAdv[i] / SLG_stDirN[i];
         line = StringFormat("%s %d本後: n=%d(実効%.0f)  順方向≥%.2fATR %.0f%% / 逆行 %.0f%%",
                             type, H, SLG_stDirN[i], nEff, thr, fav * 100.0, adv * 100.0);
         if(hasBase)
            line += StringFormat("  [基準%s %.0f%% %+.0fpt]", bName, pNeuB * 100.0, (fav - pNeuB) * 100.0);
        }
      else
        {
         double hit = (double)SLG_stHit[i] / SLG_stN[i];
         line = StringFormat("%s%s %d本後: n=%d(実効%.0f)  ≥%.2fATR動いた %.0f%%",
                             SLG_IsBaseType(type) ? "【基準】" : "", type, H, SLG_stN[i], nEff, thr, hit * 100.0);
         if(hasBase)
            line += StringFormat("  [基準%s %.0f%% %+.0fpt]", bName, pMaxB * 100.0, (hit - pMaxB) * 100.0);
        }
      if(nEff < SLG_MinN) line += " ※実効件数不足";

      int k = ArraySize(SLG_statLines);
      ArrayResize(SLG_statLines, k + 1);
      SLG_statLines[k] = line;
     }
  }

//+------------------------------------------------------------------+
//| 続く急変の整理                                                     |
//| 急変(SPIKE系)は、同じ急変が続く間に何度も記録されることがある。      |
//| 同じ種類・銘柄・時間足で、直前のイベントから SLG_EpisodeBars 本以内に |
//| 記録されたものは、同じ急変の続きとして、集計から除く(最初の1件だけ残す)。|
//| 続きが続く限り連鎖して除く(直前のイベントが除かれたものでも基準にする)。|
//| 古い記録に残っている重複の掃除にもなる。                           |
//+------------------------------------------------------------------+
void SLG_BuildDropped()
  {
   ArrayResize(SLG_dpKeys, 0);
   ArrayResize(SLG_dpVals, 0);
   SLG_dpCnt = 0;

   string lastKeys[];
   int    lastVals[];
   int    lastCnt = 0;
   int nEv = ArraySize(SLG_evId);
   for(int e = 0; e < nEv; e++)
     {
      if(StringFind(SLG_evType[e], "SPIKE") != 0)
         continue;
      string gk = SLG_evType[e] + "|" + SLG_evSym[e] + "|" + IntegerToString(SLG_evTf[e]);
      int last = SLG_MapGet(lastKeys, lastVals, gk, 0);
      int t = (int)SLG_evTime[e];
      if(last > 0 && t >= last && t - last <= SLG_EpisodeBars * SLG_evTf[e])
         SLG_MapPut(SLG_dpKeys, SLG_dpVals, SLG_dpCnt, SLG_evId[e], 1);
      SLG_MapPut(lastKeys, lastVals, lastCnt, gk, t);   // 除いたものも含め、常に直前の時刻を更新する
     }
  }

//+------------------------------------------------------------------+
//| results.csv を読み、集計を作り直す                                  |
//|  fillDone=true なら評価済みキーも復元する                          |
//|  全ての評価本数が揃ったイベントだけを集計に入れる                    |
//+------------------------------------------------------------------+
void SLG_ReadResults(const bool fillDone)
  {
   ArrayResize(SLG_stType, 0);
   ArrayResize(SLG_stTf,   0);
   ArrayResize(SLG_stH,    0);
   ArrayResize(SLG_stN,    0);
   ArrayResize(SLG_stEff,  0);
   ArrayResize(SLG_stHit,  0);
   ArrayResize(SLG_stHit2, 0);
   ArrayResize(SLG_stHit3, 0);
   ArrayResize(SLG_stSum,  0);
   ArrayResize(SLG_stNorm, 0);
   ArrayResize(SLG_stUp,   0);
   ArrayResize(SLG_stDn,   0);
   ArrayResize(SLG_stDirN, 0);
   ArrayResize(SLG_stFav,  0);
   ArrayResize(SLG_stAdv,  0);
   ArrayResize(SLG_stFavSum, 0);
   ArrayResize(SLG_stWinEnd, 0);
   SLG_pending = 0;
   SLG_BuildDropped();   // 続く急変の2件目以降を、集計から除くイベントとして洗い出す
   if(fillDone)
     {
      ArrayResize(SLG_dnKeys, 0);
      ArrayResize(SLG_dnVals, 0);
      SLG_dnCnt = 0;
     }

   int h = FileOpen(SLG_ResultsPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      SLG_BuildStatLines();
      return;
     }

   //--- 1回目: 全行を読み、イベントごとの行数を数える ---
   string   rId[];
   string   rType[];
   int      rTf[];
   int      rH[];
   datetime rTime[];
   double   rUp[];
   double   rDn[];
   double   rMax[];
   int      rSig[];
   int      rN = 0;
   string   cKeys[];
   int      cVals[];
   int      cCnt = 0;

   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0 || StringFind(line, "id,") == 0)
         continue;

      string f[];
      int n = StringSplit(line, ',', f);
      if(n < 12)
         continue;

      int H = (int)StringToInteger(f[7]);
      if(fillDone)
         SLG_AddDone(f[0] + "|" + IntegerToString(H));
      if(SLG_MapFind(SLG_dpKeys, f[0]) >= 0)
         continue;   // 続く急変の2件目以降は集計に入れない(評価済みの記録としては残す)
      SLG_MapPut(cKeys, cVals, cCnt, f[0], SLG_MapGet(cKeys, cVals, f[0], 0) + 1);

      // features に sig=up / sig=down があるものは、期待方向と逆行を分けて集計する
      string feat = (n >= 13) ? f[12] : "";
      int sigDir = 0;
      if(StringFind(feat, "sig=up") >= 0)        sigDir = 1;
      else if(StringFind(feat, "sig=down") >= 0) sigDir = -1;

      ArrayResize(rId,   rN + 1, 1024);
      ArrayResize(rType, rN + 1, 1024);
      ArrayResize(rTf,   rN + 1, 1024);
      ArrayResize(rH,    rN + 1, 1024);
      ArrayResize(rTime, rN + 1, 1024);
      ArrayResize(rUp,   rN + 1, 1024);
      ArrayResize(rDn,   rN + 1, 1024);
      ArrayResize(rMax,  rN + 1, 1024);
      ArrayResize(rSig,  rN + 1, 1024);
      rId[rN]   = f[0];
      rType[rN] = f[1];
      rTf[rN]   = (int)StringToInteger(f[3]);
      rH[rN]    = H;
      rTime[rN] = (datetime)StringToInteger(f[4]);
      rUp[rN]   = StringToDouble(f[9]);
      rDn[rN]   = StringToDouble(f[10]);
      rMax[rN]  = StringToDouble(f[11]);
      rSig[rN]  = sigDir;
      rN++;
     }
   FileClose(h);
   if(rN > 999999)
     {
      Print("SLG_ReadResults: 結果の行数が100万行を超えたため、古い分を無視します。results.csvを退避してください");
      rN = 999999;
     }

   //--- 2回目: 全本数が揃ったイベントだけを、時刻順に集計する ---
   int nH = MathMax(1, ArraySize(SLG_horizons));

   // 「全時間足」の集計では、含まれる最長の時間足を、時間窓の長さに使う(種類×本数ごと)
   string mtKeys[];
   int    mtVals[];
   int    mtCnt = 0;
   double ord[];
   int    nOrd = 0;
   for(int r = 0; r < rN; r++)
     {
      if(SLG_MapGet(cKeys, cVals, rId[r], 0) < nH)
         continue;   // 評価が途中のイベントは入れない(本数の間で対象を揃えるため)
      string mk = rType[r] + "|" + IntegerToString(rH[r]);
      if(rTf[r] > SLG_MapGet(mtKeys, mtVals, mk, 0))
         SLG_MapPut(mtKeys, mtVals, mtCnt, mk, rTf[r]);
      // 時刻順に並べるためのキー(時刻×100万 + 行番号)。倍精度で正確に表せる範囲に収まる
      ArrayResize(ord, nOrd + 1, 1024);
      ord[nOrd] = (double)rTime[r] * 1000000.0 + (double)(r % 1000000);
      nOrd++;
     }
   ArraySort(ord);   // 時刻の昇順(同じ時刻は行番号の順)
   for(int q = 0; q < nOrd; q++)
     {
      long kk = (long)ord[q];
      int r = (int)(kk % 1000000);
      int tfSec = rTf[r];
      int H = rH[r];
      datetime tm = rTime[r];

      //--- 実効件数: 最初のイベントから「評価期間の長さ」の窓を作り、窓に入るイベントは同じ塊と数える ---
      int maxTf = SLG_MapGet(mtKeys, mtVals, rType[r] + "|" + IntegerToString(H), tfSec);
      int iAll = SLG_StatIndex(rType[r], 0, H);
      bool newAll = (tm >= SLG_stWinEnd[iAll]);
      if(newAll)
         SLG_stWinEnd[iAll] = tm + (datetime)(H * MathMax(1, maxTf));
      SLG_StatAdd(iAll, H, rMax[r], rUp[r], rDn[r], rSig[r], newAll);

      if(tfSec > 0)
        {
         int iTf = SLG_StatIndex(rType[r], tfSec, H);
         bool newTf = (tm >= SLG_stWinEnd[iTf]);
         if(newTf)
            SLG_stWinEnd[iTf] = tm + (datetime)(H * tfSec);
         SLG_StatAdd(iTf, H, rMax[r], rUp[r], rDn[r], rSig[r], newTf);
        }
     }

   //--- 評価待ちのイベント数(全本数が揃っていないもの) ---
   int nEv = ArraySize(SLG_evId);
   for(int e = 0; e < nEv; e++)
     {
      if(SLG_MapFind(SLG_dpKeys, SLG_evId[e]) >= 0)
         continue;   // 集計から除くイベントは数えない
      if(SLG_MapGet(cKeys, cVals, SLG_evId[e], 0) < nH)
         SLG_pending++;
     }

   SLG_BuildStatLines();
  }

//+------------------------------------------------------------------+
//| events.csv を読み込んでメモリに復元                                |
//+------------------------------------------------------------------+
void SLG_LoadEvents()
  {
   ArrayResize(SLG_evId,    0);
   ArrayResize(SLG_evType,  0);
   ArrayResize(SLG_evSym,   0);
   ArrayResize(SLG_evTf,    0);
   ArrayResize(SLG_evTime,  0);
   ArrayResize(SLG_evPrice, 0);
   ArrayResize(SLG_evAtr,   0);
   ArrayResize(SLG_evFeat,  0);
   ArrayResize(SLG_idKeys,  0);
   ArrayResize(SLG_idVals,  0);
   SLG_idCnt = 0;

   int h = FileOpen(SLG_EventsPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return;

   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      StringTrimLeft(line);
      StringTrimRight(line);
      if(StringLen(line) == 0 || StringFind(line, "id,") == 0)
         continue;

      string f[];
      int n = StringSplit(line, ',', f);
      if(n < 8)
         continue;

      int k = ArraySize(SLG_evId);
      ArrayResize(SLG_evId,    k + 1, 1024);
      ArrayResize(SLG_evType,  k + 1, 1024);
      ArrayResize(SLG_evSym,   k + 1, 1024);
      ArrayResize(SLG_evTf,    k + 1, 1024);
      ArrayResize(SLG_evTime,  k + 1, 1024);
      ArrayResize(SLG_evPrice, k + 1, 1024);
      ArrayResize(SLG_evAtr,   k + 1, 1024);
      ArrayResize(SLG_evFeat,  k + 1, 1024);
      SLG_evId[k]    = f[0];
      SLG_evType[k]  = f[1];
      SLG_evSym[k]   = f[2];
      SLG_evTf[k]    = (int)StringToInteger(f[3]);
      SLG_evTime[k]  = (datetime)StringToInteger(f[4]);
      SLG_evPrice[k] = StringToDouble(f[5]);
      SLG_evAtr[k]   = StringToDouble(f[6]);
      SLG_evFeat[k]  = f[7];
      SLG_AddEventId(f[0]);
     }
   FileClose(h);
  }

//+------------------------------------------------------------------+
//| 初期化。OnInit() から1回呼ぶ                                       |
//+------------------------------------------------------------------+
bool SLG_Init()
  {
   SLG_ready = false;
   SLG_on = SLG_Enable;
   // フォルダは記録がONの時だけ作る(ジャンクションを作る前に空フォルダができるのを避ける)
   if(SLG_on)
      FolderCreate(SLG_Folder); // 既に存在する場合はfalseが返るが問題ない

   //--- 評価する本数をパース
   string parts[];
   int np = StringSplit(SLG_Horizons, ',', parts);
   ArrayResize(SLG_horizons, 0);
   for(int i = 0; i < np; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      int v = (int)StringToInteger(s);
      if(v > 0)
        {
         int k = ArraySize(SLG_horizons);
         ArrayResize(SLG_horizons, k + 1);
         SLG_horizons[k] = v;
        }
     }
   if(ArraySize(SLG_horizons) == 0)
     {
      ArrayResize(SLG_horizons, 3);
      SLG_horizons[0] = 3;
      SLG_horizons[1] = 6;
      SLG_horizons[2] = 12;
     }

   SLG_LoadEvents();
   SLG_ReadResults(true);
   SLG_lastEval = 0;
   SLG_ready = true;
   return true;
  }

//+------------------------------------------------------------------+
//| イベントを記録する(同じidは二重に記録しない)                       |
//|  type      : "TRANSITION" / "SPIKE" / "BASE" など(英数字・_・+のみ) |
//|  entryTime : 基準時刻(サーバー時間)                               |
//|  price     : 基準価格                                              |
//|  atr       : 基準ATR(価格の絶対値。変動をATR倍で評価するのに使う)  |
//|  features  : "key=value;key=value" 形式(カンマは使わない)          |
//+------------------------------------------------------------------+
void SLG_LogEvent(const string type, const string symbol, const ENUM_TIMEFRAMES tf,
                  const datetime entryTime, const double price, const double atr,
                  const string features)
  {
   if(!SLG_ready || !SLG_on)
      return;

   int tfSec = PeriodSeconds(tf);
   string id = StringFormat("%s|%s|%d|%I64d", type, symbol, tfSec, (long)entryTime);
   if(SLG_EventExists(id))
      return;

   int k = ArraySize(SLG_evId);
   ArrayResize(SLG_evId,    k + 1, 1024);
   ArrayResize(SLG_evType,  k + 1, 1024);
   ArrayResize(SLG_evSym,   k + 1, 1024);
   ArrayResize(SLG_evTf,    k + 1, 1024);
   ArrayResize(SLG_evTime,  k + 1, 1024);
   ArrayResize(SLG_evPrice, k + 1, 1024);
   ArrayResize(SLG_evAtr,   k + 1, 1024);
   ArrayResize(SLG_evFeat,  k + 1, 1024);
   SLG_evId[k]    = id;
   SLG_evType[k]  = type;
   SLG_evSym[k]   = symbol;
   SLG_evTf[k]    = tfSec;
   SLG_evTime[k]  = entryTime;
   SLG_evPrice[k] = price;
   SLG_evAtr[k]   = atr;
   SLG_evFeat[k]  = features;
   SLG_AddEventId(id);

   string line = StringFormat("%s,%s,%s,%d,%I64d,%.6f,%.6f,%s",
                              id, type, symbol, tfSec, (long)entryTime, price, atr, features);
   SLG_AppendLine(SLG_EventsPath(), line, SLG_EV_HEADER);
  }

//+------------------------------------------------------------------+
//| 評価時刻が来たイベントの結果を計算して results.csv に追記する       |
//| 毎周期呼んでよい(内部で SLG_EvalIntervalSec ごとにだけ実行)       |
//+------------------------------------------------------------------+
void SLG_EvaluatePending()
  {
   if(!SLG_ready || !SLG_on)
      return;

   datetime now = TimeCurrent();
   if(now - SLG_lastEval < SLG_EvalIntervalSec)
      return;
   SLG_lastEval = now;

   bool wrote = false;
   int nEv = ArraySize(SLG_evId);
   int nH  = ArraySize(SLG_horizons);

   for(int e = 0; e < nEv; e++)
     {
      if(SLG_evAtr[e] <= 0.0)
         continue;

      for(int hi = 0; hi < nH; hi++)
        {
         int H = SLG_horizons[hi];
         string key = SLG_evId[e] + "|" + IntegerToString(H);
         if(SLG_IsDone(key))
            continue;

         datetime tEnd = SLG_evTime[e] + (datetime)(H * SLG_evTf[e]);
         if(now < tEnd + 120)
            continue; // まだ評価期間が終わっていない

         //--- 基準時刻から評価終了までの1分足で、最高値・最安値・終値を求める
         MqlRates rates[];
         int n = CopyRates(SLG_evSym[e], PERIOD_M1, SLG_evTime[e], tEnd, rates);
         if(n <= 0)
            continue; // 1分足が取得できない場合は次回再試行

         double maxHigh = rates[0].high;
         double minLow  = rates[0].low;
         for(int j = 1; j < n; j++)
           {
            if(rates[j].high > maxHigh) maxHigh = rates[j].high;
            if(rates[j].low  < minLow)  minLow  = rates[j].low;
           }
         double lastClose = rates[n - 1].close;

         double atr       = SLG_evAtr[e];
         double price     = SLG_evPrice[e];
         double upAtr     = (maxHigh - price) / atr;
         double downAtr   = (price - minLow) / atr;
         double closeAtr  = (lastClose - price) / atr;
         double maxExcAtr = MathMax(upAtr, downAtr);

         string line = StringFormat("%s,%s,%s,%d,%I64d,%.6f,%.6f,%d,%.3f,%.3f,%.3f,%.3f,%s",
                                    SLG_evId[e], SLG_evType[e], SLG_evSym[e], SLG_evTf[e],
                                    (long)SLG_evTime[e], price, atr, H,
                                    closeAtr, upAtr, downAtr, maxExcAtr, SLG_evFeat[e]);
         if(SLG_AppendLine(SLG_ResultsPath(), line, SLG_RS_HEADER))
           {
            SLG_AddDone(key);
            wrote = true;
           }
        }
     }

   if(wrote)
      SLG_ReadResults(false); // 集計を最新化
  }

//+------------------------------------------------------------------+
//| 表示用                                                             |
//+------------------------------------------------------------------+
int SLG_GetStatLines(string &out[])
  {
   int n = ArraySize(SLG_statLines);
   ArrayResize(out, n);
   for(int i = 0; i < n; i++)
      out[i] = SLG_statLines[i];
   return n;
  }

//--- ログ記録のON/OFFを実行中に切り替える
void SLG_SetOn(const bool on)
  {
   SLG_on = on;
   if(on)
      FolderCreate(SLG_Folder);
  }

bool SLG_IsOn() { return SLG_on; }

int  SLG_EventCount() { return ArraySize(SLG_evId); }
int  SLG_DoneCount()  { return SLG_dnCnt; }
bool SLG_IsReady()    { return SLG_ready; }

//+------------------------------------------------------------------+
//| 基準の抽出(決定的な擬似乱数)                                       |
//| (銘柄・時間足・足の時刻)から決まるので、チャート切替などで           |
//| 読み込み直されても同じ足が同じ判定になり、重複や偏りが出ない。       |
//+------------------------------------------------------------------+
bool SLG_Sample(const string symbol, const int tfSec, const datetime barTime,
                const double rate, const int salt)
  {
   if(rate <= 0.0) return false;
   if(rate >= 1.0) return true;

   ulong P = 1099511628211;
   ulong h = 1469598103934665603;
   int len = StringLen(symbol);
   for(int i = 0; i < len; i++)
     {
      h ^= (ulong)StringGetCharacter(symbol, i);
      h *= P;
     }
   h ^= (ulong)tfSec;     h *= P;
   h ^= (ulong)barTime;   h *= P;
   h ^= (ulong)salt;      h *= P;

   // 最後に十分に混ぜる(SplitMix64の仕上げ)。salt違いの抽出が互いに独立になるようにする
   // 定数は16ビットずつ組み立てる(大きな16進リテラルの型が環境で変わらないようにするため)
   ulong c1 = 0xBF58;  c1 = (c1 << 16) | 0x476D;  c1 = (c1 << 16) | 0x1CE4;  c1 = (c1 << 16) | 0xE5B9;
   ulong c2 = 0x94D0;  c2 = (c2 << 16) | 0x49BB;  c2 = (c2 << 16) | 0x1331;  c2 = (c2 << 16) | 0x11EB;
   h ^= (h >> 30);  h *= c1;
   h ^= (h >> 27);  h *= c2;
   h ^= (h >> 31);

   double u = (double)((h >> 11) % 1000000) / 1000000.0;
   return (u < rate);
  }

//+------------------------------------------------------------------+
//| 検証レポート(テキスト)                                            |
//| 基準と比べた成績・信頼区間・検定結果をまとめて、テキストファイルに出す。|
//| そのファイルの内容を貼り付ければ、第三者(AI含む)に評価してもらえる。 |
//+------------------------------------------------------------------+
void SLG_AddLine(string &arr[], const string s)
  {
   int k = ArraySize(arr);
   ArrayResize(arr, k + 1, 256);
   arr[k] = s;
  }

bool SLG_WriteReport()
  {
   if(!SLG_ready)
      return false;

   SLG_ReadResults(false);   // 最新の結果で集計し直す

   string L[];
   int cmp = 0, sigHigh = 0, sigLow = 0;

   SLG_AddLine(L, "=== CCompression 検証レポート (集計方式 v2) ===");
   SLG_AddLine(L, "作成時刻(サーバー時間): " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
   SLG_AddLine(L, StringFormat("設定: 「動いた」=%.1fATR(評価%d本後の値。他の本数は√(本数比)で補正: 例 %s) / 評価本数=%s / 基準の抽出率 BASE=%.1f%% BASE_COMP=%.1f%% BASE_RISE=%.0f%% / 判定に必要な最小の実効件数=%d",
                               SLG_HitATR, SLG_HitRefBars,
                               (ArraySize(SLG_horizons) > 0) ? StringFormat("H=%d→%.2fATR", SLG_horizons[ArraySize(SLG_horizons) - 1], SLG_Thr(SLG_horizons[ArraySize(SLG_horizons) - 1])) : "-",
                               SLG_Horizons, SLG_BaseRate * 100.0, SLG_BaseCompRate * 100.0, SLG_BaseRiseRate * 100.0, SLG_MinN));

   //--- イベントの件数と期間 ---
   int nEv = ArraySize(SLG_evId);
   datetime t0 = 0, t1 = 0;
   string tNames[];
   int    tCnt[];
   for(int i = 0; i < nEv; i++)
     {
      if(t0 == 0 || SLG_evTime[i] < t0) t0 = SLG_evTime[i];
      if(SLG_evTime[i] > t1) t1 = SLG_evTime[i];
      int found = -1;
      for(int k = 0; k < ArraySize(tNames); k++)
         if(tNames[k] == SLG_evType[i]) { found = k; break; }
      if(found < 0)
        {
         found = ArraySize(tNames);
         ArrayResize(tNames, found + 1);
         ArrayResize(tCnt, found + 1);
         tNames[found] = SLG_evType[i];
         tCnt[found] = 0;
        }
      tCnt[found]++;
     }
   SLG_AddLine(L, StringFormat("記録イベント: %d件  うち評価待ち(全本数が揃っていない): %d件  期間: %s 〜 %s (%.1f日間)  評価済み行: %d",
                               nEv, SLG_pending, TimeToString(t0, TIME_DATE), TimeToString(t1, TIME_DATE),
                               (t1 > t0) ? (double)(t1 - t0) / 86400.0 : 0.0, SLG_dnCnt));
   string cnts = "種類別の記録件数: ";
   for(int k = 0; k < ArraySize(tNames); k++)
      cnts += StringFormat("%s=%d ", tNames[k], tCnt[k]);
   SLG_AddLine(L, cnts);
   SLG_AddLine(L, "※集計に入るのは、全ての評価本数が揃ったイベントだけ。");
   SLG_AddLine(L, "");

   //--- 登場する種類(基準を除く)と時間足の一覧 ---
   string sigTypes[];
   string baseTypes[];
   int    tfs[];
   int nSt = ArraySize(SLG_stType);
   for(int i = 0; i < nSt; i++)
     {
      bool isBase = SLG_IsBaseType(SLG_stType[i]);
      if(isBase)
        {
         bool hasB = false;
         for(int k = 0; k < ArraySize(baseTypes); k++)
            if(baseTypes[k] == SLG_stType[i]) { hasB = true; break; }
         if(!hasB) { int m = ArraySize(baseTypes); ArrayResize(baseTypes, m + 1); baseTypes[m] = SLG_stType[i]; }
        }
      else
        {
         bool has = false;
         for(int k = 0; k < ArraySize(sigTypes); k++)
            if(sigTypes[k] == SLG_stType[i]) { has = true; break; }
         if(!has) { int m = ArraySize(sigTypes); ArrayResize(sigTypes, m + 1); sigTypes[m] = SLG_stType[i]; }
        }
      if(SLG_stTf[i] > 0)
        {
         bool has2 = false;
         for(int k = 0; k < ArraySize(tfs); k++)
            if(tfs[k] == SLG_stTf[i]) { has2 = true; break; }
         if(!has2) { int m2 = ArraySize(tfs); ArrayResize(tfs, m2 + 1); tfs[m2] = SLG_stTf[i]; }
        }
     }
   // 時間足を短い順に並べる
   for(int a = 0; a < ArraySize(tfs) - 1; a++)
      for(int b = a + 1; b < ArraySize(tfs); b++)
         if(tfs[b] < tfs[a]) { int tmp = tfs[a]; tfs[a] = tfs[b]; tfs[b] = tmp; }

   int nH = ArraySize(SLG_horizons);

   //--- [1] 基準 ---
   SLG_AddLine(L, "[1] 基準(圧縮やシグナルと無関係に、無作為に抜き出した足の成績)");
   SLG_AddLine(L, "    BASE=すべての足 / BASE_COMP=圧縮中の足 / BASE_RISE=前の足が強い圧縮で、ATR・BB幅が上昇し、Scoreは下がっていない足");
   SLG_AddLine(L, "    シグナルの成績は、これと比べて初めて意味を持つ。(実効)=評価期間が重なるイベントを1つの塊と数えた件数");
   for(int bt = 0; bt < ArraySize(baseTypes); bt++)
      for(int hi = 0; hi < nH; hi++)
        {
         int si = SLG_FindStat(baseTypes[bt], 0, SLG_horizons[hi]);
         if(si >= 0) SLG_AddLine(L, "  " + SLG_FmtLine(si, cmp, sigHigh, sigLow));
        }
   SLG_AddLine(L, "");

   //--- [2] シグナル(全時間足) ---
   SLG_AddLine(L, "[2] シグナルの成績(全時間足まとめ)と、基準との比較");
   for(int ty = 0; ty < ArraySize(sigTypes); ty++)
     {
      for(int hi = 0; hi < nH; hi++)
        {
         int si = SLG_FindStat(sigTypes[ty], 0, SLG_horizons[hi]);
         if(si >= 0) SLG_AddLine(L, "  " + SLG_FmtLine(si, cmp, sigHigh, sigLow));
        }
      SLG_AddLine(L, "");
     }

   //--- [3] 時間足別(件数10以上のみ) ---
   SLG_AddLine(L, "[3] 時間足別(件数10以上のみ表示)");
   for(int tf = 0; tf < ArraySize(tfs); tf++)
     {
      for(int bt = 0; bt < ArraySize(baseTypes); bt++)
         for(int hi = 0; hi < nH; hi++)
           {
            int si = SLG_FindStat(baseTypes[bt], tfs[tf], SLG_horizons[hi]);
            if(si >= 0 && SLG_stN[si] >= 10) SLG_AddLine(L, "  " + SLG_FmtLine(si, cmp, sigHigh, sigLow));
           }
      for(int ty = 0; ty < ArraySize(sigTypes); ty++)
         for(int hi = 0; hi < nH; hi++)
           {
            int si = SLG_FindStat(sigTypes[ty], tfs[tf], SLG_horizons[hi]);
            int cnt = (si >= 0) ? ((SLG_stDirN[si] > 0) ? SLG_stDirN[si] : SLG_stN[si]) : 0;
            if(si >= 0 && cnt >= 10) SLG_AddLine(L, "  " + SLG_FmtLine(si, cmp, sigHigh, sigLow));
           }
     }
   SLG_AddLine(L, "");

   //--- [4] 読み方の注意 ---
   SLG_AddLine(L, "[4] 読み方の注意");
   SLG_AddLine(L, StringFormat("  ・判定した比較は%d件(シグナルと基準の両方で実効件数%d以上)。うち、基準より有意に高い(p<0.05)=%d件、低い=%d件。", cmp, SLG_MinN, sigHigh, sigLow));
   SLG_AddLine(L, "    比較を多数行うと、偶然でもp<0.05のものが約5%出る。高いものは追試が必要(別の期間で再現するか)。");
   SLG_AddLine(L, "  ・「動いた」は、評価期間内の最大変動(上でも下でも)が基準以上。基準は評価本数ごとに √(本数) で補正している。固定の2ATR・3ATRの割合も併記。");
   SLG_AddLine(L, "  ・信頼区間とp値は、実効件数で計算している。実効件数は、評価期間(評価本数×時間足)の時間窓で数える:");
   SLG_AddLine(L, "    最初のイベントから評価期間の長さの窓を作り、窓に入るイベントは、通貨ペアが違っても1つの塊と数える(評価期間が重なると結果が独立でないため)。");
   SLG_AddLine(L, "    保守的な数え方なので、実効件数は件数よりかなり少なくなる。それでも、時間帯をまたぐ相関(円・ドルの動きなど)は残る。");
   SLG_AddLine(L, StringFormat("  ・急変(SPIKE系)は、同じ銘柄・時間足で%d本以内に続けて記録されたものを、1つの急変と数えている(集計から除いた件数: %d件)。", SLG_EpisodeBars, SLG_dpCnt));
   SLG_AddLine(L, "  ・TRANSITIONは BASE_RISE(強い圧縮の後でボラが上昇し、Scoreは下がっていない足)と比べる。TRANSITIONの条件に「ボラ上昇」が含まれるため、");
   SLG_AddLine(L, "    ボラが戻り始めたから動く、という当たり前の性質を除いて、Scoreが下がることの効果を見るため。");
   SLG_AddLine(L, "  ・方向つきのシグナル(WOLFE5・TRANSITION+ICHI)は、期待した方向に動いた割合(順方向)と逆行の割合を表示。基準は「片方向」の割合と比べている。");
   SLG_AddLine(L, "  ・急変(SPIKE)は、検知した瞬間(足の途中)を起点にしている。基準は足の終値を起点にしているため、起点の取り方が少し違う。");
   SLG_AddLine(L, "  ・SPIKE_V1 と SPIKE_V2 は、急変の旧判定(V1)と新判定(V2)を、それぞれ独立に記録したもの。両者の成績を比べられる。");
   SLG_AddLine(L, "  ・件数が少ない間は結論にしない。調整した条件は、調整に使っていない別の期間で確かめること。");

   //--- ファイルへ出力(UTF-16。メモ帳で開け、そのままコピーして貼り付けられる) ---
   FolderCreate(SLG_Folder);
   int fh = FileOpen(SLG_ReportPath(), FILE_WRITE | FILE_TXT | FILE_UNICODE);
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("SLG_WriteReport: レポートを書き込めません %s (error=%d)", SLG_ReportPath(), GetLastError());
      return false;
     }
   for(int i = 0; i < ArraySize(L); i++)
      FileWriteString(fh, L[i] + "\r\n");
   FileClose(fh);
   PrintFormat("検証レポートを出力しました: MQL5\\Files\\%s", SLG_ReportPath());
   return true;
  }

//--- 自動出力(毎周期呼んでよい。ログ記録中のみ、SLG_ReportIntervalMin分ごとに出力)
datetime g_slgLastReport = 0;

void SLG_AutoReport()
  {
   if(!SLG_ready || SLG_ReportIntervalMin <= 0)
      return;
   datetime now = TimeCurrent();
   if(g_slgLastReport == 0)
     {
      g_slgLastReport = now;   // 起動直後は出さない
      return;
     }
   if(now - g_slgLastReport < SLG_ReportIntervalMin * 60)
      return;
   g_slgLastReport = now;
   if(SLG_on)
      SLG_WriteReport();
  }
//+------------------------------------------------------------------+

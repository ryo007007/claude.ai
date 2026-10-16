//+------------------------------------------------------------------+
//|                                              SignalLogger.mqh     |
//|  結果記録エンジン(検証用)                                          |
//|                                                                    |
//|  シグナル(TRANSITION・急変など)が出た瞬間を events.csv に記録し、   |
//|  その後 N本(その時間足の本数)経過した時点で、実際にどれだけ動いたかを |
//|  ATR倍で計算して results.csv に追記する。                          |
//|                                                                    |
//|  保存先: MQL5/Files/<SLG_Folder>/CCOMP_events.csv                 |
//|          MQL5/Files/<SLG_Folder>/CCOMP_results.csv                |
//|  (CSVなのでExcelで開いて集計できる)                               |
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
//|  【注意】スキャナーは1つのチャートだけで動かしてください。         |
//|  複数チャートで同時に動かすと、評価結果が重複して記録されます。    |
//+------------------------------------------------------------------+
#property strict

input group "=== 結果記録(検証ログ) ==="
input bool   SLG_Enable          = true;            // 起動時にログを記録する(チャート上のボタンで随時切替可)
input string SLG_Horizons        = "3,6,12";        // 評価する本数(その時間足の本数、カンマ区切り)
input double SLG_HitATR          = 1.0;             // 「動いた」とみなす最大変動幅(ATRの何倍か)
input string SLG_Folder          = "Verification log"; // MQL5/Files内の保存フォルダ(ジャンクション経由でclaude.ai内に置く)
input int    SLG_EvalIntervalSec = 60;              // 未評価分のチェック間隔(秒)
input double SLG_BaseRate        = 0.01;            // 基準の記録(BASE): すべての確定足から無作為に抜き出す割合
input double SLG_BaseCompRate    = 0.05;            // 基準の記録(BASE_COMP): 圧縮中の確定足から抜き出す割合
input int    SLG_MinN            = 30;              // レポートで「判定できる」とみなす最小件数(これ未満は参考値)
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

//--- 評価済み("id|horizon")
string   SLG_done[];

//--- 集計(種類 × 時間足 × 評価本数)。SLG_stTf=0 は「全時間足」
string   SLG_stType[];
int      SLG_stTf[];
int      SLG_stH[];
int      SLG_stN[];
int      SLG_stHit[];      // 最大変動が HitATR 以上だった件数
double   SLG_stSum[];      // 最大変動の合計(ATR倍)
int      SLG_stUp[];       // 上方向に HitATR 以上動いた件数
int      SLG_stDn[];       // 下方向に HitATR 以上動いた件数
int      SLG_stDirN[];     // 方向つきシグナル(features に sig=up/down があるもの)の件数
int      SLG_stFav[];      // そのうち、期待方向に HitATR 以上動いた件数
int      SLG_stAdv[];      // そのうち、逆方向に HitATR 以上動いた件数
double   SLG_stFavSum[];   // 期待方向への最大変動の合計(ATR倍)
string   SLG_statLines[];

int      SLG_horizons[];
datetime SLG_lastEval = 0;
bool     SLG_ready = false;   // 初期化済み(過去ログの読込が済んでいる)
bool     SLG_on    = false;   // ログ記録のON/OFF(実行中に切り替え可能)

//+------------------------------------------------------------------+
string SLG_EventsPath()  { return SLG_Folder + "\\CCOMP_events.csv"; }
string SLG_ResultsPath() { return SLG_Folder + "\\CCOMP_results.csv"; }

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
bool SLG_EventExists(const string id)
  {
   int n = ArraySize(SLG_evId);
   for(int i = 0; i < n; i++)
      if(SLG_evId[i] == id)
         return true;
   return false;
  }

bool SLG_IsDone(const string key)
  {
   int n = ArraySize(SLG_done);
   for(int i = 0; i < n; i++)
      if(SLG_done[i] == key)
         return true;
   return false;
  }

void SLG_AddDone(const string key)
  {
   int n = ArraySize(SLG_done);
   ArrayResize(SLG_done, n + 1);
   SLG_done[n] = key;
  }

//+------------------------------------------------------------------+
//| 集計(種類 × 時間足 × 評価本数)                                    |
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
   ArrayResize(SLG_stHit,  n + 1);
   ArrayResize(SLG_stSum,  n + 1);
   ArrayResize(SLG_stUp,   n + 1);
   ArrayResize(SLG_stDn,   n + 1);
   ArrayResize(SLG_stDirN, n + 1);
   ArrayResize(SLG_stFav,  n + 1);
   ArrayResize(SLG_stAdv,  n + 1);
   ArrayResize(SLG_stFavSum, n + 1);
   SLG_stType[n] = type;
   SLG_stTf[n]   = tfSec;
   SLG_stH[n]    = H;
   SLG_stN[n]    = 0;
   SLG_stHit[n]  = 0;
   SLG_stSum[n]  = 0.0;
   SLG_stUp[n]   = 0;
   SLG_stDn[n]   = 0;
   SLG_stDirN[n] = 0;
   SLG_stFav[n]  = 0;
   SLG_stAdv[n]  = 0;
   SLG_stFavSum[n] = 0.0;
   return n;
  }

void SLG_StatAdd(const int si, const double maxExc, const double upAtr, const double dnAtr, const int sigDir)
  {
   SLG_stN[si]++;
   if(maxExc >= SLG_HitATR) SLG_stHit[si]++;
   SLG_stSum[si] += maxExc;
   if(upAtr >= SLG_HitATR)  SLG_stUp[si]++;
   if(dnAtr >= SLG_HitATR)  SLG_stDn[si]++;
   if(sigDir != 0)
     {
      double fav = (sigDir > 0) ? upAtr : dnAtr;
      double adv = (sigDir > 0) ? dnAtr : upAtr;
      SLG_stDirN[si]++;
      if(fav >= SLG_HitATR) SLG_stFav[si]++;
      if(adv >= SLG_HitATR) SLG_stAdv[si]++;
      SLG_stFavSum[si] += fav;
     }
  }

//+------------------------------------------------------------------+
//| 基準(対照)との比較                                                |
//|  BASE      : すべての確定足から無作為に抜き出した足                |
//|  BASE_COMP : 圧縮中(COMPRESSION以上)の確定足から無作為に抜き出した足 |
//|  圧縮解除(TRANSITION)や急変は「圧縮中の足」から出るので、          |
//|  BASE_COMP と比べるのが公平。それ以外は BASE と比べる。             |
//+------------------------------------------------------------------+
bool SLG_IsBaseType(const string t)
  {
   return (t == "BASE" || t == "BASE_COMP");
  }

string SLG_BaseTypeFor(const string type)
  {
   if(StringFind(type, "TRANSITION") == 0 || StringFind(type, "SPIKE") == 0)
      return "BASE_COMP";
   return "BASE";
  }

//--- 比較に使う基準を探す。BASE_COMPの件数が足りなければBASEで代用する
//--- pMax: 基準で「最大変動がHitATR以上」の割合 / pNeutral: 基準で「片方向にHitATR以上」の割合(上と下の平均)
bool SLG_GetBase(const string type, const int tfSec, const int H,
                 double &pMax, double &pNeutral, int &nBase, string &baseName)
  {
   string want = SLG_BaseTypeFor(type);
   int bi = SLG_FindStat(want, tfSec, H);
   if(bi < 0 || SLG_stN[bi] < SLG_MinN)
     {
      int b2 = SLG_FindStat("BASE", tfSec, H);
      if(b2 >= 0 && (bi < 0 || SLG_stN[b2] > SLG_stN[bi]))
        {
         bi = b2;
         want = "BASE";
        }
     }
   if(bi < 0 || SLG_stN[bi] <= 0)
      return false;
   nBase = SLG_stN[bi];
   baseName = want;
   pMax = (double)SLG_stHit[bi] / nBase;
   pNeutral = (double)(SLG_stUp[bi] + SLG_stDn[bi]) / (2.0 * nBase);
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
   double a = z * MathSqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n));
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
   double se = MathSqrt(pp * (1.0 - pp) * (1.0 / n1 + 1.0 / n2));
   if(se <= 0.0)
      return 1.0;
   return 2.0 * (1.0 - SLG_NormCdf(MathAbs(diff / se)));
  }

string SLG_Verdict(const int n, const double diff, const double p)
  {
   if(n < SLG_MinN)
      return "n不足(参考値)";
   if(p < 0.05)
      return (diff > 0.0) ? "基準より高い(偶然の可能性あり・要追試)" : "基準より低い";
   return "基準との差は有意でない";
  }

//--- 1つの集計(種類×時間足×本数)を、レポートの1行にする
string SLG_FmtLine(const int si, int &cmp, int &sigHigh, int &sigLow)
  {
   string type = SLG_stType[si];
   int tf = SLG_stTf[si];
   int H  = SLG_stH[si];
   int n  = SLG_stN[si];
   string head = StringFormat("%-15s %-5s H=%-3d n=%-4d ", type, SLG_TfText(tf), H, n);
   if(n <= 0)
      return head + "(データなし)";

   if(SLG_IsBaseType(type))
     {
      double lo, hi;
      SLG_Wilson(SLG_stHit[si], n, lo, hi);
      return head + StringFormat("動いた%.1f%% [95%%CI %.0f-%.0f]  上方向%.1f%% 下方向%.1f%%  平均最大変動%.2fATR",
                                 (double)SLG_stHit[si] / n * 100.0, lo * 100.0, hi * 100.0,
                                 (double)SLG_stUp[si] / n * 100.0, (double)SLG_stDn[si] / n * 100.0,
                                 SLG_stSum[si] / n);
     }

   double pMaxB, pNeuB;
   int    nB;
   string bName;
   bool hasBase = SLG_GetBase(type, tf, H, pMaxB, pNeuB, nB, bName);

   if(SLG_stDirN[si] > 0)
     {
      //--- 方向つき: 順方向に動いた割合を、基準の「片方向」と比べる ---
      int nd = SLG_stDirN[si];
      double pf = (double)SLG_stFav[si] / nd;
      double pa = (double)SLG_stAdv[si] / nd;
      double lo, hi;
      SLG_Wilson(SLG_stFav[si], nd, lo, hi);
      string s = StringFormat("%-15s %-5s H=%-3d n=%-4d 順方向%.1f%% [95%%CI %.0f-%.0f]  逆行%.1f%%  平均順方向%.2fATR",
                              type, SLG_TfText(tf), H, nd, pf * 100.0, lo * 100.0, hi * 100.0, pa * 100.0,
                              SLG_stFavSum[si] / nd);
      s += StringFormat("  順方向-逆行 %+.1fpt", (pf - pa) * 100.0);
      if(!hasBase)
         return s + "  基準なし";
      double diff;
      double p = SLG_PValue(SLG_stFav[si], nd, pNeuB * nB, nB, diff);
      s += StringFormat("  | 基準(%s n=%d)の片方向%.1f%% → 差%+.1fpt p=%.3f  %s",
                        bName, nB, pNeuB * 100.0, diff * 100.0, p, SLG_Verdict(nd, diff, p));
      if(nd >= SLG_MinN)
        {
         cmp++;
         if(p < 0.05 && diff > 0.0) sigHigh++;
         if(p < 0.05 && diff < 0.0) sigLow++;
        }
      return s;
     }

   //--- 方向なし: 最大変動(上下どちらでも)が HitATR 以上だった割合を、基準と比べる ---
   double pHit = (double)SLG_stHit[si] / n;
   double lo, hi;
   SLG_Wilson(SLG_stHit[si], n, lo, hi);
   string s = head + StringFormat("動いた%.1f%% [95%%CI %.0f-%.0f]  平均最大変動%.2fATR",
                                  pHit * 100.0, lo * 100.0, hi * 100.0, SLG_stSum[si] / n);
   if(!hasBase)
      return s + "  基準なし";
   double diff;
   double p = SLG_PValue(SLG_stHit[si], n, pMaxB * nB, nB, diff);
   s += StringFormat("  | 基準(%s n=%d) %.1f%% → 差%+.1fpt p=%.3f  %s",
                     bName, nB, pMaxB * 100.0, diff * 100.0, p, SLG_Verdict(n, diff, p));
   if(n >= SLG_MinN)
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
      string line;

      double pMaxB, pNeuB;
      int    nB;
      string bName;
      bool hasBase = (!SLG_IsBaseType(type)) && SLG_GetBase(type, 0, H, pMaxB, pNeuB, nB, bName);

      if(SLG_stDirN[i] > 0)
        {
         double fav = (double)SLG_stFav[i] / SLG_stDirN[i];
         double adv = (double)SLG_stAdv[i] / SLG_stDirN[i];
         line = StringFormat("%s %d本後: n=%d  順方向%.1fATR以上 %.0f%% / 逆行 %.0f%%",
                             type, H, SLG_stDirN[i], SLG_HitATR, fav * 100.0, adv * 100.0);
         if(hasBase)
            line += StringFormat("  [基準%s %.0f%% %+.0fpt]", bName, pNeuB * 100.0, (fav - pNeuB) * 100.0);
         if(SLG_stDirN[i] < SLG_MinN) line += " ※n不足";
        }
      else
        {
         double hit = (double)SLG_stHit[i] / SLG_stN[i];
         line = StringFormat("%s%s %d本後: n=%d  %.1fATR以上動いた %.0f%%",
                             SLG_IsBaseType(type) ? "【基準】" : "", type, H, SLG_stN[i], SLG_HitATR, hit * 100.0);
         if(hasBase)
            line += StringFormat("  [基準%s %.0f%% %+.0fpt]", bName, pMaxB * 100.0, (hit - pMaxB) * 100.0);
         if(SLG_stN[i] < SLG_MinN) line += " ※n不足";
        }

      int k = ArraySize(SLG_statLines);
      ArrayResize(SLG_statLines, k + 1);
      SLG_statLines[k] = line;
     }
  }

//+------------------------------------------------------------------+
//| results.csv を読み、集計を作り直す。fillDone=true なら評価済みキーも復元 |
//+------------------------------------------------------------------+
void SLG_ReadResults(const bool fillDone)
  {
   ArrayResize(SLG_stType, 0);
   ArrayResize(SLG_stTf,   0);
   ArrayResize(SLG_stH,    0);
   ArrayResize(SLG_stN,    0);
   ArrayResize(SLG_stHit,  0);
   ArrayResize(SLG_stSum,  0);
   ArrayResize(SLG_stUp,   0);
   ArrayResize(SLG_stDn,   0);
   ArrayResize(SLG_stDirN, 0);
   ArrayResize(SLG_stFav,  0);
   ArrayResize(SLG_stAdv,  0);
   ArrayResize(SLG_stFavSum, 0);
   if(fillDone)
      ArrayResize(SLG_done, 0);

   int h = FileOpen(SLG_ResultsPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      SLG_BuildStatLines();
      return;
     }

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

      int    tfSec  = (int)StringToInteger(f[3]);
      int    H      = (int)StringToInteger(f[7]);
      double upAtr  = StringToDouble(f[9]);
      double dnAtr  = StringToDouble(f[10]);
      double maxExc = StringToDouble(f[11]);

      if(fillDone)
         SLG_AddDone(f[0] + "|" + IntegerToString(H));

      // features に sig=up / sig=down があるものは、期待方向と逆行を分けて集計する
      string feat = (n >= 13) ? f[12] : "";
      int sigDir = 0;
      if(StringFind(feat, "sig=up") >= 0)        sigDir = 1;
      else if(StringFind(feat, "sig=down") >= 0) sigDir = -1;

      SLG_StatAdd(SLG_StatIndex(f[1], 0, H), maxExc, upAtr, dnAtr, sigDir);       // 全時間足
      if(tfSec > 0)
         SLG_StatAdd(SLG_StatIndex(f[1], tfSec, H), maxExc, upAtr, dnAtr, sigDir); // 時間足別
     }
   FileClose(h);
   SLG_BuildStatLines();
  }

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
string SLG_ReportPath() { return SLG_Folder + "\\CCOMP_report.txt"; }

void SLG_AddLine(string &arr[], const string s)
  {
   int k = ArraySize(arr);
   ArrayResize(arr, k + 1);
   arr[k] = s;
  }

bool SLG_WriteReport()
  {
   if(!SLG_ready)
      return false;

   SLG_ReadResults(false);   // 最新の結果で集計し直す

   string L[];
   int cmp = 0, sigHigh = 0, sigLow = 0;

   SLG_AddLine(L, "=== CCompression 検証レポート ===");
   SLG_AddLine(L, "作成時刻(サーバー時間): " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
   SLG_AddLine(L, StringFormat("設定: 「動いた」=%.1fATR以上 / 評価本数=%s / 基準の抽出率 BASE=%.1f%% BASE_COMP=%.1f%% / 判定に必要な最小件数=%d",
                               SLG_HitATR, SLG_Horizons, SLG_BaseRate * 100.0, SLG_BaseCompRate * 100.0, SLG_MinN));

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
   SLG_AddLine(L, StringFormat("記録イベント: %d件  期間: %s 〜 %s (%.1f日間)  評価済み行: %d",
                               nEv, TimeToString(t0, TIME_DATE), TimeToString(t1, TIME_DATE),
                               (t1 > t0) ? (double)(t1 - t0) / 86400.0 : 0.0, ArraySize(SLG_done)));
   string cnts = "種類別の件数: ";
   for(int k = 0; k < ArraySize(tNames); k++)
      cnts += StringFormat("%s=%d ", tNames[k], tCnt[k]);
   SLG_AddLine(L, cnts);
   SLG_AddLine(L, "");

   //--- 登場する種類(基準を除く)と時間足の一覧 ---
   string sigTypes[];
   int    tfs[];
   int nSt = ArraySize(SLG_stType);
   for(int i = 0; i < nSt; i++)
     {
      if(!SLG_IsBaseType(SLG_stType[i]))
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
   string baseTypes[2] = {"BASE", "BASE_COMP"};

   //--- [1] 基準 ---
   SLG_AddLine(L, "[1] 基準(圧縮やシグナルと無関係に、無作為に抜き出した足の成績)");
   SLG_AddLine(L, "    BASE=すべての足 / BASE_COMP=圧縮中の足。シグナルの成績は、これと比べて初めて意味を持つ。");
   for(int bt = 0; bt < 2; bt++)
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
      for(int bt = 0; bt < 2; bt++)
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
   SLG_AddLine(L, StringFormat("  ・比較は件数%d以上のもの%d件。うち、基準より有意に高い(p<0.05)=%d件、低い=%d件。", SLG_MinN, cmp, sigHigh, sigLow));
   SLG_AddLine(L, "    比較を多数行うと、偶然でもp<0.05のものが約5%出る。高いものは追試が必要(別の期間で再現するか)。");
   SLG_AddLine(L, "  ・同じ時刻に複数の通貨ペアで出たイベントは独立ではない(相関している)。表示のp値より、実際の確からしさは低い。");
   SLG_AddLine(L, "  ・「動いた」は、評価期間内の最大変動がATRのHitATR倍以上。方向を問わない(上でも下でも)。");
   SLG_AddLine(L, "  ・方向つきのシグナル(WOLFE5・TRANSITION+ICHI)は、期待した方向に動いた割合(順方向)と逆行の割合を表示。基準は「片方向」の割合と比べている。");
   SLG_AddLine(L, "  ・急変(SPIKE)は、検知した瞬間(足の途中)を起点にしている。基準は足の終値を起点にしているため、起点の取り方が少し違う。");
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
      ArrayResize(SLG_evId,    k + 1);
      ArrayResize(SLG_evType,  k + 1);
      ArrayResize(SLG_evSym,   k + 1);
      ArrayResize(SLG_evTf,    k + 1);
      ArrayResize(SLG_evTime,  k + 1);
      ArrayResize(SLG_evPrice, k + 1);
      ArrayResize(SLG_evAtr,   k + 1);
      ArrayResize(SLG_evFeat,  k + 1);
      SLG_evId[k]    = f[0];
      SLG_evType[k]  = f[1];
      SLG_evSym[k]   = f[2];
      SLG_evTf[k]    = (int)StringToInteger(f[3]);
      SLG_evTime[k]  = (datetime)StringToInteger(f[4]);
      SLG_evPrice[k] = StringToDouble(f[5]);
      SLG_evAtr[k]   = StringToDouble(f[6]);
      SLG_evFeat[k]  = f[7];
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
//|  type      : "TRANSITION" / "SPIKE" など(英数字のみ)              |
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
   ArrayResize(SLG_evId,    k + 1);
   ArrayResize(SLG_evType,  k + 1);
   ArrayResize(SLG_evSym,   k + 1);
   ArrayResize(SLG_evTf,    k + 1);
   ArrayResize(SLG_evTime,  k + 1);
   ArrayResize(SLG_evPrice, k + 1);
   ArrayResize(SLG_evAtr,   k + 1);
   ArrayResize(SLG_evFeat,  k + 1);
   SLG_evId[k]    = id;
   SLG_evType[k]  = type;
   SLG_evSym[k]   = symbol;
   SLG_evTf[k]    = tfSec;
   SLG_evTime[k]  = entryTime;
   SLG_evPrice[k] = price;
   SLG_evAtr[k]   = atr;
   SLG_evFeat[k]  = features;

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
int  SLG_DoneCount()  { return ArraySize(SLG_done); }
bool SLG_IsReady()    { return SLG_ready; }
//+------------------------------------------------------------------+

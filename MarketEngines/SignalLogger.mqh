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
//|  評価は1分足データで行うため、チャートを閉じていても次回起動時に    |
//|  未評価の分をまとめて評価する(再起動・チャート切替に強い)。        |
//|                                                                    |
//|  【注意】スキャナーは1つのチャートだけで動かしてください。         |
//|  複数チャートで同時に動かすと、評価結果が重複して記録されます。    |
//+------------------------------------------------------------------+
#property strict

input group "=== 結果記録(検証ログ) ==="
input bool   SLG_Enable          = true;            // 記録を有効にする
input string SLG_Horizons        = "3,6,12";        // 評価する本数(その時間足の本数、カンマ区切り)
input double SLG_HitATR          = 1.0;             // 「動いた」とみなす最大変動幅(ATRの何倍か)
input string SLG_Folder          = "MarketEngines"; // MQL5/Files内の保存フォルダ
input int    SLG_EvalIntervalSec = 60;              // 未評価分のチェック間隔(秒)

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

//--- 集計
string   SLG_stType[];
int      SLG_stH[];
int      SLG_stN[];
int      SLG_stHit[];
double   SLG_stSum[];
string   SLG_statLines[];

int      SLG_horizons[];
datetime SLG_lastEval = 0;
bool     SLG_ready = false;

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
//| 集計(type × horizon)                                              |
//+------------------------------------------------------------------+
int SLG_StatIndex(const string type, const int H)
  {
   int n = ArraySize(SLG_stType);
   for(int i = 0; i < n; i++)
      if(SLG_stType[i] == type && SLG_stH[i] == H)
         return i;
   ArrayResize(SLG_stType, n + 1);
   ArrayResize(SLG_stH,    n + 1);
   ArrayResize(SLG_stN,    n + 1);
   ArrayResize(SLG_stHit,  n + 1);
   ArrayResize(SLG_stSum,  n + 1);
   SLG_stType[n] = type;
   SLG_stH[n]    = H;
   SLG_stN[n]    = 0;
   SLG_stHit[n]  = 0;
   SLG_stSum[n]  = 0.0;
   return n;
  }

void SLG_BuildStatLines()
  {
   int n = ArraySize(SLG_stType);
   ArrayResize(SLG_statLines, n);
   for(int i = 0; i < n; i++)
     {
      double hitRate = (SLG_stN[i] > 0) ? (double)SLG_stHit[i] / SLG_stN[i] * 100.0 : 0.0;
      double avgExc  = (SLG_stN[i] > 0) ? SLG_stSum[i] / SLG_stN[i] : 0.0;
      SLG_statLines[i] = StringFormat("%s %d本後: n=%d  %.1fATR以上動いた %.0f%%  平均最大変動 %.2fATR",
                                      SLG_stType[i], SLG_stH[i], SLG_stN[i], SLG_HitATR, hitRate, avgExc);
     }
  }

//+------------------------------------------------------------------+
//| results.csv を読み、集計を作り直す。fillDone=true なら評価済みキーも復元 |
//+------------------------------------------------------------------+
void SLG_ReadResults(const bool fillDone)
  {
   ArrayResize(SLG_stType, 0);
   ArrayResize(SLG_stH,    0);
   ArrayResize(SLG_stN,    0);
   ArrayResize(SLG_stHit,  0);
   ArrayResize(SLG_stSum,  0);
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

      int    H      = (int)StringToInteger(f[7]);
      double maxExc = StringToDouble(f[11]);

      if(fillDone)
         SLG_AddDone(f[0] + "|" + IntegerToString(H));

      int si = SLG_StatIndex(f[1], H);
      SLG_stN[si]++;
      if(maxExc >= SLG_HitATR)
         SLG_stHit[si]++;
      SLG_stSum[si] += maxExc;
     }
   FileClose(h);
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
   if(!SLG_Enable)
      return false;

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
   if(!SLG_ready)
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
   if(!SLG_ready)
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

int  SLG_EventCount() { return ArraySize(SLG_evId); }
int  SLG_DoneCount()  { return ArraySize(SLG_done); }
bool SLG_IsReady()    { return SLG_ready; }
//+------------------------------------------------------------------+

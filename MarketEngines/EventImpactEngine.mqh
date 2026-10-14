//+------------------------------------------------------------------+
//|                                        EventImpactEngine.mqh      |
//|  指標インパクトエンジン                                            |
//|                                                                    |
//|  チャートの通貨ペアに関係する経済指標を取得し、                    |
//|    ・重要度が「高」の指標                       → クラス2(赤)     |
//|    ・重要度は低いが「前回、大きく動いた」指標   → クラス1(その他) |
//|    ・重要でもなく、前回も動いていない指標       → 表示しない       |
//|  に分類する。時刻は日本時間(JST)に変換して返す。                   |
//|                                                                    |
//|  「前回大きく動いたか」の判定:                                    |
//|    その指標の過去の発表(直近 EVI_HistReleases 回)について、        |
//|    発表から EVI_ImpactWindowMin 分間の値幅(5分足)を、             |
//|    発表直前の30分足ATRで割った倍率を求める。                       |
//|    直近の発表の倍率が EVI_BigMoveATR 以上なら「大きく動いた」。     |
//|    (通貨ペアごとに結果が違う。例: 米指標はUSDJPYでは大きく動く     |
//|     が、EURGBPではほとんど動かない)                              |
//|                                                                    |
//|  【制約】                                                         |
//|  ・経済指標カレンダーはライブ環境のみ(ストラテジーテスター不可)。  |
//|  ・過去の値動きは5分足の履歴が必要。古い発表で履歴が足りない場合は  |
//|    判定から除外する。                                              |
//|  ・カレンダーの時刻はサーバー時間として扱う。ずれる場合は           |
//|    EVI_TimeCorrectionMin で補正する。                              |
//|  ・ニュース記事の発表は取得できない。                              |
//+------------------------------------------------------------------+
#property strict

input group "=== 指標ライン: 取得範囲 ==="
input int  EVI_FutureHours       = 48;  // 何時間先までの指標を取得するか
input int  EVI_PastHours         = 72;  // 過去の指標も表示する時間(検証用。0=過去は表示しない)
input int  EVI_RefreshMin        = 10;  // カレンダーの再取得間隔(分)
input int  EVI_TimeCorrectionMin = 0;   // カレンダー時刻の補正(分)。ずれる場合に調整

input group "=== 指標ライン: 表示する指標 ==="
input bool   EVI_ShowHigh           = true; // 重要度「高」の指標を表示する(赤)
input bool   EVI_ShowBigMover       = true; // 重要度が低くても「前回大きく動いた」指標を表示する
input double EVI_BigMoveATR         = 1.5;  // 「大きく動いた」とみなす値幅(30分足ATRの何倍か)
input int    EVI_HistReleases       = 4;    // 動きを調べる過去の発表回数(平均を参考表示)
input int    EVI_ImpactWindowMin    = 30;   // 発表から何分間の値幅を見るか
input int    EVI_OtherMinImportance = 1;    // 「その他」に含める最低の重要度(1=低 2=中)
input int    EVI_EvalPerCycle       = 4;    // 1周期(1秒)に評価する指標の数(画面が固まらないように分割)

string   g_eviSymbol = "";
int      g_eviAtrHandle = INVALID_HANDLE;
string   g_eviCurs[];                 // この通貨ペアに関係する通貨

//--- 取得した指標(時刻の昇順)
ulong    g_eviId[];
string   g_eviCur[];
datetime g_eviTime[];                 // カレンダーの時刻(サーバー時間)
int      g_eviImp[];                  // 重要度 1=低 2=中 3=高
string   g_eviName[];

//--- 値動きの評価結果(発表1件ごとのキャッシュ = イベントID + 発表時刻)
//--- 「前回」は、その発表より前の発表を指す。過去の指標でも、その発表自体の動きは判定に含めない
ulong    g_eviCacheId[];
datetime g_eviCacheTime[];
double   g_eviCacheLast[];            // 前回の発表の値幅倍率(-1=算出不能)
double   g_eviCacheAvg[];             // 直近数回の平均倍率
int      g_eviCacheN[];               // 算出できた発表回数
double   g_eviCacheActual[];          // この発表自体の値幅倍率(発表から時間が経ったもののみ。-1=未算出)
int      g_eviCacheTries[];           // 評価を試みた回数
datetime g_eviCacheStamp[];

datetime g_eviLastFetch = 0;
bool     g_eviOk = false;
string   g_eviStatus = "未取得";
int      g_eviEvaluated = 0;

//+------------------------------------------------------------------+
bool EVI_IsMajor(const string cur)
  {
   return (cur == "USD" || cur == "EUR" || cur == "GBP" || cur == "JPY" ||
           cur == "AUD" || cur == "NZD" || cur == "CAD" || cur == "CHF");
  }

//+------------------------------------------------------------------+
//| 初期化: 対象の通貨ペアと、値動き評価に使うATRハンドルを用意する    |
//+------------------------------------------------------------------+
bool EVI_Init(const string symbol)
  {
   g_eviSymbol = symbol;
   g_eviLastFetch = 0;
   g_eviOk = false;
   g_eviStatus = "未取得";
   g_eviEvaluated = 0;
   ArrayResize(g_eviId, 0);
   ArrayResize(g_eviCur, 0);
   ArrayResize(g_eviTime, 0);
   ArrayResize(g_eviImp, 0);
   ArrayResize(g_eviName, 0);
   ArrayResize(g_eviCacheId, 0);
   ArrayResize(g_eviCacheTime, 0);
   ArrayResize(g_eviCacheLast, 0);
   ArrayResize(g_eviCacheAvg, 0);
   ArrayResize(g_eviCacheN, 0);
   ArrayResize(g_eviCacheActual, 0);
   ArrayResize(g_eviCacheTries, 0);
   ArrayResize(g_eviCacheStamp, 0);

   //--- 通貨ペアを構成する通貨(主要8通貨のみ)。金・指数・暗号資産は決済通貨(USD等)を使う
   string base  = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) < 3)  base  = StringSubstr(symbol, 0, 3);
   if(StringLen(quote) < 3) quote = StringSubstr(symbol, 3, 3);

   ArrayResize(g_eviCurs, 0);
   if(EVI_IsMajor(base))
     {
      ArrayResize(g_eviCurs, 1);
      g_eviCurs[0] = base;
     }
   if(EVI_IsMajor(quote) && quote != base)
     {
      int n = ArraySize(g_eviCurs);
      ArrayResize(g_eviCurs, n + 1);
      g_eviCurs[n] = quote;
     }
   if(ArraySize(g_eviCurs) == 0)
     {
      ArrayResize(g_eviCurs, 1);
      g_eviCurs[0] = "USD";
     }

   g_eviAtrHandle = iATR(symbol, PERIOD_M30, 14);
   if(g_eviAtrHandle == INVALID_HANDLE)
     {
      Print("EVI_Init: iATRハンドルの作成に失敗しました");
      return false;
     }
   return true;
  }

void EVI_Deinit()
  {
   if(g_eviAtrHandle != INVALID_HANDLE)
     {
      IndicatorRelease(g_eviAtrHandle);
      g_eviAtrHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| 時刻の変換                                                         |
//+------------------------------------------------------------------+
//--- カレンダーの時刻 → チャートに描く時刻(補正込み)
datetime EVI_DrawTime(const datetime calTime)
  {
   return calTime + (datetime)(EVI_TimeCorrectionMin * 60);
  }

//--- チャートに描く時刻(サーバー時間) → 日本時間
datetime EVI_ToJST(const datetime serverTime)
  {
   long off = (long)TimeTradeServer() - (long)TimeGMT();   // サーバーのUTCとの差(夏時間込み)
   off = ((off + 450) / 900) * 900;                        // 15分単位に丸める(ティックの遅れによる誤差を除く)
   return (datetime)((long)serverTime - off + 9 * 3600);
  }

//--- 日本時間の表示文字列。今日(日本時間)と同じ日なら "HH:MM"、違えば "MM/DD HH:MM"
string EVI_JstText(const datetime serverTime)
  {
   datetime jst = EVI_ToJST(serverTime);
   datetime jstNow = EVI_ToJST(TimeTradeServer());
   MqlDateTime a, b;
   TimeToStruct(jst, a);
   TimeToStruct(jstNow, b);
   if(a.year == b.year && a.mon == b.mon && a.day == b.day)
      return StringFormat("%02d:%02d", a.hour, a.min);
   return StringFormat("%02d/%02d %02d:%02d", a.mon, a.day, a.hour, a.min);
  }

string EVI_ImpText(const int imp)
  {
   if(imp >= 3) return "高";
   if(imp == 2) return "中";
   return "低";
  }

//+------------------------------------------------------------------+
//| 過去の値動きの評価                                                 |
//+------------------------------------------------------------------+
//--- 過去の発表時刻Tpについて、発表からEVI_ImpactWindowMin分間の値幅 / 発表直前の30分足ATR
//--- 戻り値: 倍率。履歴不足などで算出できない場合は -1
double EVI_RatioAt(const datetime Tp)
  {
   int w = EVI_ImpactWindowMin;
   if(w < 5) w = 5;

   MqlRates r[];
   int n = CopyRates(g_eviSymbol, PERIOD_M5, Tp, Tp + (datetime)(w * 60 - 1), r);
   if(n < MathMax(2, w / 5 - 2))
      return -1.0;

   double hi = r[0].high;
   double lo = r[0].low;
   for(int i = 1; i < n; i++)
     {
      if(r[i].high > hi) hi = r[i].high;
      if(r[i].low  < lo) lo = r[i].low;
     }

   int sh = iBarShift(g_eviSymbol, PERIOD_M30, Tp, false);
   if(sh < 0)
      return -1.0;
   double a[];
   if(CopyBuffer(g_eviAtrHandle, 0, sh + 1, 1, a) <= 0)
      return -1.0;
   if(a[0] <= 0.0)
      return -1.0;

   return (hi - lo) / a[0];
  }

int EVI_CacheIndex(const ulong id, const datetime t)
  {
   int n = ArraySize(g_eviCacheId);
   for(int i = 0; i < n; i++)
      if(g_eviCacheId[i] == id && g_eviCacheTime[i] == t)
         return i;
   return -1;
  }

//--- 発表時刻Tの指標について評価する
//---   前回の動き: Tより前の発表のうち、直近 EVI_HistReleases 回の値幅倍率
//---   今回の動き: この発表自体の値幅倍率(発表から十分な時間が経っている場合のみ)
void EVI_EvaluateEvent(const ulong id, const datetime T)
  {
   double last = -1.0;
   double avg  = -1.0;
   double actual = -1.0;
   int    cnt  = 0;
   datetime now = TimeTradeServer();
   int w = MathMax(5, EVI_ImpactWindowMin);
   datetime limit = now - (datetime)(w * 60 + 300);   // これより前の発表なら、発表後の値動きが確定している

   //--- Tより前の発表だけを対象にする(その発表自体の動きは判定に含めない) ---
   datetime to = T - 60;
   if(to > limit) to = limit;
   datetime from = now - (datetime)(400 * 86400);

   MqlCalendarValue hist[];
   if(CalendarValueHistoryByEvent(id, hist, from, to))
     {
      int total = ArraySize(hist);
      datetime times[];
      ArrayResize(times, total);
      for(int i = 0; i < total; i++)
         times[i] = hist[i].time;
      ArraySort(times);   // 古い順

      int startIdx = MathMax(0, total - MathMax(1, EVI_HistReleases));
      double sum = 0.0;
      for(int i = startIdx; i < total; i++)
        {
         double ratio = EVI_RatioAt(times[i]);
         if(ratio < 0.0)
            continue;
         sum += ratio;
         cnt++;
         last = ratio;   // 古い順に処理するので、最後に残るのが「前回」
        }
      if(cnt > 0)
         avg = sum / cnt;
     }

   //--- この発表自体の値動き ---
   if(T <= limit)
      actual = EVI_RatioAt(T);

   int ci = EVI_CacheIndex(id, T);
   if(ci < 0)
     {
      ci = ArraySize(g_eviCacheId);
      ArrayResize(g_eviCacheId,     ci + 1);
      ArrayResize(g_eviCacheTime,   ci + 1);
      ArrayResize(g_eviCacheLast,   ci + 1);
      ArrayResize(g_eviCacheAvg,    ci + 1);
      ArrayResize(g_eviCacheN,      ci + 1);
      ArrayResize(g_eviCacheActual, ci + 1);
      ArrayResize(g_eviCacheTries,  ci + 1);
      ArrayResize(g_eviCacheStamp,  ci + 1);
      g_eviCacheId[ci]    = id;
      g_eviCacheTime[ci]  = T;
      g_eviCacheTries[ci] = 0;
     }
   g_eviCacheLast[ci]   = last;
   g_eviCacheAvg[ci]    = avg;
   g_eviCacheN[ci]      = cnt;
   g_eviCacheActual[ci] = actual;
   g_eviCacheTries[ci]++;
   g_eviCacheStamp[ci]  = now;
  }

//--- この発表をいま(再)評価する必要があるか
bool EVI_NeedEval(const int ci, const datetime T, const datetime now)
  {
   if(ci < 0)
      return true;

   int w = MathMax(5, EVI_ImpactWindowMin);
   bool actualReady = (T <= now - (datetime)(w * 60 + 300));
   bool prevOk   = (g_eviCacheN[ci] > 0);
   bool actualOk = (!actualReady) || (g_eviCacheActual[ci] >= 0.0);

   // データが足りなかったものは、2分ごとに数回だけ再試行する
   if((!prevOk || !actualOk) && g_eviCacheTries[ci] < 4)
      return (now - g_eviCacheStamp[ci] >= 120);

   // これからの発表は、12時間ごとに前回の動きを更新する
   if(!actualReady && now - g_eviCacheStamp[ci] >= 12 * 3600)
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| カレンダーから指標の一覧を取得する                                 |
//+------------------------------------------------------------------+
void EVI_FetchList()
  {
   datetime now  = TimeTradeServer();
   datetime from = (EVI_PastHours > 0) ? now - (datetime)(EVI_PastHours * 3600) : now - 120;
   datetime to   = now + (datetime)(EVI_FutureHours * 3600);

   ulong    tId[];
   string   tCur[];
   datetime tTime[];
   int      tImp[];
   string   tName[];
   bool anyOk = false;
   int  lastErr = 0;

   int nc = ArraySize(g_eviCurs);
   for(int c = 0; c < nc; c++)
     {
      MqlCalendarValue vals[];
      ResetLastError();
      if(!CalendarValueHistory(vals, from, to, NULL, g_eviCurs[c]))
        {
         lastErr = GetLastError();
         continue;
        }
      anyOk = true;

      int n = ArraySize(vals);
      for(int k = 0; k < n; k++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[k].event_id, ev))
            continue;
         if(ev.type == CALENDAR_TYPE_HOLIDAY)
            continue;
         int imp = (int)ev.importance;
         if(imp <= 0)
            continue;

         int m = ArraySize(tId);
         ArrayResize(tId,   m + 1);
         ArrayResize(tCur,  m + 1);
         ArrayResize(tTime, m + 1);
         ArrayResize(tImp,  m + 1);
         ArrayResize(tName, m + 1);
         tId[m]   = vals[k].event_id;
         tCur[m]  = g_eviCurs[c];
         tTime[m] = vals[k].time;
         tImp[m]  = imp;
         tName[m] = ev.name;
        }
     }

   if(!anyOk)
     {
      g_eviOk = false;
      g_eviStatus = StringFormat("カレンダー取得不可(error=%d)", lastErr);
      return;
     }

   //--- 時刻の昇順に並べ替える(同時刻は重要度の高い順)。挿入ソート
   int m2 = ArraySize(tId);
   for(int a = 1; a < m2; a++)
     {
      ulong    kId   = tId[a];
      string   kCur  = tCur[a];
      datetime kTime = tTime[a];
      int      kImp  = tImp[a];
      string   kName = tName[a];
      int b = a - 1;
      while(b >= 0 && (tTime[b] > kTime || (tTime[b] == kTime && tImp[b] < kImp)))
        {
         tId[b + 1]   = tId[b];
         tCur[b + 1]  = tCur[b];
         tTime[b + 1] = tTime[b];
         tImp[b + 1]  = tImp[b];
         tName[b + 1] = tName[b];
         b--;
        }
      tId[b + 1]   = kId;
      tCur[b + 1]  = kCur;
      tTime[b + 1] = kTime;
      tImp[b + 1]  = kImp;
      tName[b + 1] = kName;
     }

   ArrayResize(g_eviId,   m2);
   ArrayResize(g_eviCur,  m2);
   ArrayResize(g_eviTime, m2);
   ArrayResize(g_eviImp,  m2);
   ArrayResize(g_eviName, m2);
   for(int i = 0; i < m2; i++)
     {
      g_eviId[i]   = tId[i];
      g_eviCur[i]  = tCur[i];
      g_eviTime[i] = tTime[i];
      g_eviImp[i]  = tImp[i];
      g_eviName[i] = tName[i];
     }
   g_eviOk = true;
   g_eviStatus = StringFormat("取得済(%d件)", m2);
  }

//+------------------------------------------------------------------+
//| 毎周期(1秒ごと)に呼ぶ。一覧の再取得と、値動きの評価を少しずつ進める |
//+------------------------------------------------------------------+
void EVI_Refresh()
  {
   if(g_eviAtrHandle == INVALID_HANDLE)
      return;

   datetime now = TimeTradeServer();
   if(g_eviLastFetch == 0 || now - g_eviLastFetch >= EVI_RefreshMin * 60)
     {
      g_eviLastFetch = now;
      EVI_FetchList();
     }

   //--- 値動きの評価(1周期あたり EVI_EvalPerCycle 件まで)。これからの発表を先に評価する ---
   int done = 0;
   int n = ArraySize(g_eviId);
   for(int pass = 0; pass < 2; pass++)
     {
      for(int i = 0; i < n && done < MathMax(1, EVI_EvalPerCycle); i++)
        {
         bool upcoming = (g_eviTime[i] >= now - 3600);
         if((pass == 0) != upcoming)
            continue;
         int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
         if(!EVI_NeedEval(ci, g_eviTime[i], now))
            continue;
         EVI_EvaluateEvent(g_eviId[i], g_eviTime[i]);
         done++;
        }
     }

   int ev = 0;
   for(int i = 0; i < n; i++)
     {
      int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
      if(ci >= 0 && g_eviCacheN[ci] > 0)
         ev++;
     }
   g_eviEvaluated = ev;
  }

//+------------------------------------------------------------------+
//| 取得結果の参照                                                     |
//+------------------------------------------------------------------+
int    EVI_Count()      { return ArraySize(g_eviId); }
string EVI_StatusText() { return g_eviStatus; }

double EVI_LastRatio(const int i)
  {
   int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
   return (ci >= 0) ? g_eviCacheLast[ci] : -1.0;
  }

double EVI_AvgRatio(const int i)
  {
   int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
   return (ci >= 0) ? g_eviCacheAvg[ci] : -1.0;
  }

int EVI_ValidN(const int i)
  {
   int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
   return (ci >= 0) ? g_eviCacheN[ci] : 0;
  }

//--- この発表自体の値動き(倍率)。発表から時間が経っていない場合や算出不能の場合は -1
double EVI_ActualRatio(const int i)
  {
   int ci = EVI_CacheIndex(g_eviId[i], g_eviTime[i]);
   return (ci >= 0) ? g_eviCacheActual[ci] : -1.0;
  }

//--- 表示クラス: 2=重要(赤) / 1=その他で大きく動く / 0=表示しない
int EVI_Class(const int i)
  {
   if(g_eviImp[i] >= 3 && EVI_ShowHigh)
      return 2;
   if(EVI_ShowBigMover && g_eviImp[i] >= EVI_OtherMinImportance)
     {
      double last = EVI_LastRatio(i);
      if(last >= EVI_BigMoveATR)
         return 1;
     }
   return 0;
  }
//+------------------------------------------------------------------+

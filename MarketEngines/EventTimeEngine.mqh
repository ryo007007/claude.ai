//+------------------------------------------------------------------+
//|                                          EventTimeEngine.mqh      |
//|  指標発表・市場開場までの残り時間エンジン                          |
//|                                                                    |
//|  ・MT5内蔵の経済指標カレンダーから、各通貨の次の重要指標と         |
//|    直前の指標を取得する(EVT_Refresh)                             |
//|  ・ウェリントン/シドニー/東京/ロンドン/NYの開場時刻までの          |
//|    残り時間を、夏時間を考慮して計算する                            |
//|  ・通貨ペア(例 NZDJPY)に対して、NZDとJPYの指標・開場のうち         |
//|    近いものを返す(EVT_GetInfo)                                   |
//|                                                                    |
//|  【制約】                                                         |
//|  ・経済指標カレンダーは、MT5がブローカーに接続されたライブ環境で    |
//|    のみ使える(ストラテジーテスターでは使えない)。                |
//|  ・ニュース記事の発表は、MQL5から読み取る手段がないため対象外。     |
//|  ・夏時間は一般的なルールで計算する。祝日や臨時の変更は反映しない。 |
//+------------------------------------------------------------------+
#property strict

input group "=== 指標発表・市場開場エンジン ==="
input bool EVT_UseCalendar    = true;  // 経済指標カレンダーを使う
input int  EVT_MinImportance  = 3;     // 対象にする指標の重要度(1=低 2=中 3=高)
input int  EVT_RefreshMin     = 15;    // カレンダーの再取得間隔(分)
input int  EVT_LookaheadHours = 48;    // 何時間先までの指標を取得するか
input int  EVT_LookbackMin    = 180;   // 発表直後の判定用に、何分前から取得するか
input bool EVT_UseSessions    = true;  // 市場開場(ウェリントン/シドニー/東京/ロンドン/NY)を使う
input int  EVT_MaxWindowMin   = 240;   // 予兆スコアに反映する先読み時間の上限(分)

//--- 取得した指標のキャッシュ
string   g_evtCur[];
datetime g_evtTime[];
int      g_evtImp[];
string   g_evtName[];
datetime g_evtLastRefresh = 0;
bool     g_evtOk = false;
string   g_evtStatus = "未取得";

//--- 市場セッション(0=ウェリントン 1=シドニー 2=東京 3=ロンドン 4=NY)
string g_evtSessionName[5] = {"Wellington", "Sydney", "Tokyo", "London", "NewYork"};
int    g_evtOpenHour[5]    = {8, 8, 9, 8, 8};      // 現地の開場時刻(時)
int    g_evtStdOffset[5]   = {12, 10, 9, 0, -5};   // 標準時のUTCとの差(時間)

//--- 1つの通貨ペアについての指標・開場情報
struct EVT_Info
  {
   int    minToNext;     // 次の指標まで(分)。なし=-1
   string nextCur;       // 次の指標の通貨
   string nextName;      // 次の指標の名称
   int    nextImp;       // 次の指標の重要度(1-3)
   int    minSinceLast;  // 直前の指標から(分)。なし=-1
   string lastCur;
   string lastName;
   int    minToSession;  // 次の開場まで(分)。なし=-1
   string sessionName;   // 次に開場する市場
   double score;         // 予兆スコアへの寄与(0〜1)
  };

//+------------------------------------------------------------------+
//| 日付計算                                                           |
//+------------------------------------------------------------------+
int EVT_YearOf(const datetime t)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   return d.year;
  }

//--- 指定月の第n曜日(nth=1〜4)、またはnth=5で最終の曜日。dow: 0=日曜。戻り値は0:00(UTC日付)
datetime EVT_NthWeekday(const int year, const int month, const int dow, const int nth)
  {
   MqlDateTime dt;
   dt.year = year; dt.mon = month; dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime first = StructToTime(dt);
   TimeToStruct(first, dt);
   int firstDow = dt.day_of_week;

   if(nth < 5)
      return first + (datetime)((((dow - firstDow + 7) % 7) + (nth - 1) * 7) * 86400);

   MqlDateTime dn;
   dn.year = (month == 12) ? year + 1 : year;
   dn.mon  = (month == 12) ? 1 : month + 1;
   dn.day = 1; dn.hour = 0; dn.min = 0; dn.sec = 0;
   datetime nextFirst = StructToTime(dn);
   datetime lastDay = nextFirst - 86400;
   MqlDateTime dl;
   TimeToStruct(lastDay, dl);
   return lastDay - (datetime)(((dl.day_of_week - dow + 7) % 7) * 86400);
  }

//--- 夏時間の判定(引数はUTCの時刻)
bool EVT_IsUSDST(const datetime utc)
  {
   int y = EVT_YearOf(utc);
   datetime st = EVT_NthWeekday(y, 3, 0, 2) + 7 * 3600;   // 3月第2日曜 2:00(EST) = 07:00 UTC
   datetime en = EVT_NthWeekday(y, 11, 0, 1) + 6 * 3600;  // 11月第1日曜 2:00(EDT) = 06:00 UTC
   return (utc >= st && utc < en);
  }

bool EVT_IsEUDST(const datetime utc)
  {
   int y = EVT_YearOf(utc);
   datetime st = EVT_NthWeekday(y, 3, 0, 5) + 1 * 3600;   // 3月最終日曜 01:00 UTC
   datetime en = EVT_NthWeekday(y, 10, 0, 5) + 1 * 3600;  // 10月最終日曜 01:00 UTC
   return (utc >= st && utc < en);
  }

bool EVT_IsAUDST(const datetime utc)   // シドニー: 10月第1日曜〜4月第1日曜
  {
   int y = EVT_YearOf(utc);
   datetime en = EVT_NthWeekday(y, 4, 0, 1) - 8 * 3600;
   datetime st = EVT_NthWeekday(y, 10, 0, 1) - 8 * 3600;
   return (utc < en || utc >= st);
  }

bool EVT_IsNZDST(const datetime utc)   // ウェリントン: 9月最終日曜〜4月第1日曜
  {
   int y = EVT_YearOf(utc);
   datetime en = EVT_NthWeekday(y, 4, 0, 1) - 10 * 3600;
   datetime st = EVT_NthWeekday(y, 9, 0, 5) - 10 * 3600;
   return (utc < en || utc >= st);
  }

//--- セッションsの、指定時刻(UTC)におけるUTCとの差(秒。夏時間込み)
int EVT_OffsetSec(const int s, const datetime utc)
  {
   int off = g_evtStdOffset[s] * 3600;
   switch(s)
     {
      case 0: if(EVT_IsNZDST(utc)) off += 3600; break;
      case 1: if(EVT_IsAUDST(utc)) off += 3600; break;
      case 3: if(EVT_IsEUDST(utc)) off += 3600; break;
      case 4: if(EVT_IsUSDST(utc)) off += 3600; break;
      default: break;
     }
   return off;
  }

//+------------------------------------------------------------------+
//| セッションsの「次の開場」と「直近の開場」(UTC)を求める            |
//+------------------------------------------------------------------+
bool EVT_SessionOpenTimes(const int s, const datetime utcNow, datetime &nextOpen, datetime &lastOpen)
  {
   nextOpen = 0;
   lastOpen = 0;
   long nowL  = (long)utcNow;
   long day0L = nowL - nowL % 86400;

   for(int d = -2; d <= 3; d++)
     {
      datetime L = (datetime)(day0L + (long)d * 86400);   // 現地日付(UTC 0:00で代用)
      MqlDateTime dt;
      TimeToStruct(L, dt);
      if(dt.day_of_week == 0 || dt.day_of_week == 6)
         continue; // 土日は開場なし

      int openSec = g_evtOpenHour[s] * 3600;
      datetime guess = L + (datetime)(openSec - g_evtStdOffset[s] * 3600);
      int off = EVT_OffsetSec(s, guess);
      datetime t = L + (datetime)(openSec - off);

      if(t > utcNow)
        {
         if(nextOpen == 0 || t < nextOpen) nextOpen = t;
        }
      else
        {
         if(t > lastOpen) lastOpen = t;
        }
     }
   return (nextOpen > 0);
  }

//--- 通貨 → 開場する市場(-1=なし)
int EVT_CurrencySession(const string cur)
  {
   if(cur == "NZD") return 0;
   if(cur == "AUD") return 1;
   if(cur == "JPY") return 2;
   if(cur == "GBP" || cur == "EUR" || cur == "CHF") return 3;
   if(cur == "USD" || cur == "CAD") return 4;
   return -1;
  }

//+------------------------------------------------------------------+
//| 経済指標カレンダーの取得(EVT_RefreshMin分ごとにだけ実際に取得)    |
//+------------------------------------------------------------------+
void EVT_Refresh()
  {
   if(!EVT_UseCalendar)
     {
      g_evtOk = false;
      g_evtStatus = "無効";
      return;
     }

   datetime now = TimeTradeServer();
   if(g_evtLastRefresh != 0 && now - g_evtLastRefresh < EVT_RefreshMin * 60)
      return;
   g_evtLastRefresh = now;

   datetime from = now - EVT_LookbackMin * 60;
   datetime to   = now + (datetime)EVT_LookaheadHours * 3600;
   string curs[8] = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF"};

   string   tCur[];
   datetime tTime[];
   int      tImp[];
   string   tName[];
   bool anyOk = false;
   int  lastErr = 0;

   for(int c = 0; c < 8; c++)
     {
      MqlCalendarValue vals[];
      ResetLastError();
      if(!CalendarValueHistory(vals, from, to, NULL, curs[c]))
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
         if(imp < EVT_MinImportance)
            continue;

         int m = ArraySize(tCur);
         ArrayResize(tCur,  m + 1);
         ArrayResize(tTime, m + 1);
         ArrayResize(tImp,  m + 1);
         ArrayResize(tName, m + 1);
         tCur[m]  = curs[c];
         tTime[m] = vals[k].time;
         tImp[m]  = imp;
         tName[m] = ev.name;
        }
     }

   if(anyOk)
     {
      int total = ArraySize(tCur);
      ArrayResize(g_evtCur,  total);
      ArrayResize(g_evtTime, total);
      ArrayResize(g_evtImp,  total);
      ArrayResize(g_evtName, total);
      for(int i = 0; i < total; i++)
        {
         g_evtCur[i]  = tCur[i];
         g_evtTime[i] = tTime[i];
         g_evtImp[i]  = tImp[i];
         g_evtName[i] = tName[i];
        }
      g_evtOk = true;
      g_evtStatus = StringFormat("取得済(%d件)", total);
     }
   else
     {
      g_evtOk = false;
      g_evtStatus = StringFormat("取得できません(error=%d)", lastErr);
     }
  }

string EVT_StatusText() { return g_evtStatus; }

//+------------------------------------------------------------------+
//| 通貨ペアの構成通貨を取得(例 NZDJPY → NZD, JPY)                    |
//+------------------------------------------------------------------+
void EVT_SymbolCurrencies(const string symbol, string &base, string &quote)
  {
   base  = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   if(StringLen(base) < 3)  base  = StringSubstr(symbol, 0, 3);
   if(StringLen(quote) < 3) quote = StringSubstr(symbol, 3, 3);
  }

//+------------------------------------------------------------------+
//| 通貨ペアについての、次の指標・開場までの残り時間と予兆への寄与     |
//|  tfSec: その時間足の秒数(先読みする時間の目安に使う)              |
//+------------------------------------------------------------------+
void EVT_GetInfo(const string symbol, const int tfSec, EVT_Info &info)
  {
   info.minToNext    = -1;
   info.nextCur      = "";
   info.nextName     = "";
   info.nextImp      = 0;
   info.minSinceLast = -1;
   info.lastCur      = "";
   info.lastName     = "";
   info.minToSession = -1;
   info.sessionName  = "";
   info.score        = 0.0;

   string base, quote;
   EVT_SymbolCurrencies(symbol, base, quote);

   //--- 経済指標 ---
   if(EVT_UseCalendar && g_evtOk)
     {
      datetime nowS = TimeTradeServer();
      datetime bestNext = 0;
      datetime bestLast = 0;
      int n = ArraySize(g_evtCur);
      for(int i = 0; i < n; i++)
        {
         if(g_evtCur[i] != base && g_evtCur[i] != quote)
            continue;
         datetime t = g_evtTime[i];
         if(t >= nowS)
           {
            if(bestNext == 0 || t < bestNext || (t == bestNext && g_evtImp[i] > info.nextImp))
              {
               bestNext = t;
               info.nextCur  = g_evtCur[i];
               info.nextName = g_evtName[i];
               info.nextImp  = g_evtImp[i];
              }
           }
         else
           {
            if(t > bestLast)
              {
               bestLast = t;
               info.lastCur  = g_evtCur[i];
               info.lastName = g_evtName[i];
              }
           }
        }
      if(bestNext > 0) info.minToNext    = (int)((bestNext - nowS) / 60);
      if(bestLast > 0) info.minSinceLast = (int)((nowS - bestLast) / 60);
     }

   //--- 市場開場(2つの通貨のうち近い方) ---
   if(EVT_UseSessions)
     {
      datetime nowU = TimeGMT();
      string curs2[2];
      curs2[0] = base;
      curs2[1] = quote;
      for(int c = 0; c < 2; c++)
        {
         int s = EVT_CurrencySession(curs2[c]);
         if(s < 0) continue;
         datetime nx, ls;
         if(!EVT_SessionOpenTimes(s, nowU, nx, ls)) continue;
         int m = (int)((nx - nowU) / 60);
         if(info.minToSession < 0 || m < info.minToSession)
           {
            info.minToSession = m;
            info.sessionName  = g_evtSessionName[s];
           }
        }
     }

   //--- 予兆スコアへの寄与(0〜1): 先読み時間内で、近いほど高い ---
   int window = MathMin(EVT_MaxWindowMin, MathMax(15, tfSec / 60 * 3));
   double se = 0.0, ss = 0.0;
   if(info.minToNext >= 0 && info.minToNext <= window)
     {
      double impW = (info.nextImp >= 3) ? 1.0 : ((info.nextImp == 2) ? 0.7 : 0.4);
      se = impW * (1.0 - (double)info.minToNext / window);
     }
   if(info.minToSession >= 0 && info.minToSession <= window)
      ss = 0.5 * (1.0 - (double)info.minToSession / window); // 開場は指標より影響が小さいので半分
   info.score = MathMax(se, ss);
  }
//+------------------------------------------------------------------+

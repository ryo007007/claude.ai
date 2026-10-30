//+------------------------------------------------------------------+
//|                                             MarketTimeEngine.mqh |
//| 市場時間管理と日本時間表示、経済指標連携エンジン                 |
//+------------------------------------------------------------------+
#property copyright "Market Time Engine"
#property version   "1.00"

#include "EventImpactEngine.mqh" // 既存の経済指標エンジンを流用

//--- 市場ステータス
enum MARKET_STATUS
  {
   STATUS_CLOSED = 0,  // クローズ中 (■)
   STATUS_OPENED = 1,  // オープン中 (▲)
   STATUS_CHANGED = 2  // 直近で状態変化 (▼)
  };

struct MarketInfo
  {
   string          name;
   MARKET_STATUS   status;
   string          timeText;
  };

MarketInfo g_tokyo;
MarketInfo g_london;
MarketInfo g_ny;

datetime g_lastJST = 0;
string   g_jstText = "";

//+------------------------------------------------------------------+
//| 初期化                                                           |
//+------------------------------------------------------------------+
bool MTE_Init()
{
   return EVI_Init(_Symbol); // 経済指標エンジンの初期化を兼ねる
}

//+------------------------------------------------------------------+
//| 終了処理                                                         |
//+------------------------------------------------------------------+
void MTE_Deinit()
{
   EVI_Deinit();
}

//+------------------------------------------------------------------+
//| 更新処理 (1秒ごとに呼び出す)                                     |
//+------------------------------------------------------------------+
void MTE_Update()
{
   EVI_Refresh(); // 経済指標データの更新

   datetime now = TimeCurrent();
   
   // サーバー時間とGMTの差分から日本時間(JST, UTC+9)を計算
   int offset = (int)((TimeGMT() - now) / 3600) + 9;
   datetime jst = now + (datetime)(offset * 3600);

   if(jst != g_lastJST)
     {
      g_lastJST = jst;
      MqlDateTime dt;
      TimeToStruct(jst, dt);
      
      // 日本時間のテキスト生成
      string dayOfWeek = "";
      switch(dt.day_of_week)
        {
         case 0: dayOfWeek = "日"; break;
         case 1: dayOfWeek = "月"; break;
         case 2: dayOfWeek = "火"; break;
         case 3: dayOfWeek = "水"; break;
         case 4: dayOfWeek = "木"; break;
         case 5: dayOfWeek = "金"; break;
         case 6: dayOfWeek = "土"; break;
        }
      g_jstText = StringFormat("%04d年%02d月%02d日 (%s) 第%d週", dt.year, dt.mon, dt.day, dayOfWeek, dt.day_of_year / 7 + 1);
      
      // 市場ステータスの更新 (簡易的な夏時間対応なしの固定時間。必要に応じて調整可能)
      UpdateMarketStatus(g_tokyo, "東京", 9, 15, dt.hour, dt.min);
      UpdateMarketStatus(g_london, "ロンドン", 16, 1, dt.hour, dt.min); // 冬時間基準
      UpdateMarketStatus(g_ny, "NY", 22, 7, dt.hour, dt.min);          // 冬時間基準
     }
}

//+------------------------------------------------------------------+
//| 市場ステータスの更新ロジック                                     |
//+------------------------------------------------------------------+
void UpdateMarketStatus(MarketInfo &m, string name, int openH, int closeH, int curH, int curM)
{
   m.name = name;
   bool isNowOpen = false;
   
   if(openH < closeH) // 同日中に開閉する場合 (例: 東京 9-15)
     {
      isNowOpen = (curH > openH || (curH == openH && curM >= 0)) && (curH < closeH);
     }
   else // 日を跨ぐ場合 (例: NY 22-7)
     {
      isNowOpen = (curH >= openH) || (curH < closeH);
     }

   if(isNowOpen)
     {
      m.status = STATUS_OPENED;
      m.timeText = StringFormat("オープン中 (%02d:%02d-)", openH, 0);
     }
   else
     {
      m.status = STATUS_CLOSED;
      m.timeText = StringFormat("クローズ中 (次は%02d:%02d)", openH, 0);
     }
}

//+------------------------------------------------------------------+
//| パネル表示用のテキスト取得                                       |
//+------------------------------------------------------------------+
string MTE_GetMarketStatusIcon(MARKET_STATUS status)
{
   if(status == STATUS_OPENED) return "▲";
   if(status == STATUS_CHANGED) return "▼";
   return "■";
}

string MTE_GetJSTText() { return g_jstText; }

//+------------------------------------------------------------------+
//| 次の経済指標情報の取得                                           |
//+------------------------------------------------------------------+
string MTE_GetNextEventText()
{
   if(!g_eviOk) return "指標データ未取得";
   
   datetime now = TimeCurrent();
   datetime nextTime = 0;
   string nextName = "";
   string nextCur = "";
   
   // EVI_Count() などで取得したリストから、現在時刻より未来で最も近い重要度3(高)のイベントを探す
   for(int i = 0; i < EVI_Count(); i++)
     {
      if(g_eviImp[i] >= 3 && g_eviTime[i] > now)
        {
         if(nextTime == 0 || g_eviTime[i] < nextTime)
           {
            nextTime = g_eviTime[i];
            nextName = g_eviName[i];
            nextCur = g_eviCur[i];
           }
        }
     }
     
   if(nextTime > 0)
     {
      int minLeft = (int)((nextTime - now) / 60);
      string timeStr = "";
      if(minLeft < 60) timeStr = StringFormat("あと%d分", minLeft);
      else timeStr = StringFormat("あと%d時間%d分", minLeft/60, minLeft%60);
      
      return StringFormat("%s [%s] %s", timeStr, nextCur, nextName);
     }
     
   return "直近に高重要度指標なし";
}
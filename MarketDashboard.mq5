//+------------------------------------------------------------------+
//|                                              MarketDashboard.mq5 |
//| 市場時間・経済指標ダッシュボード (ドラッグ移動対応)              |
//+------------------------------------------------------------------+
#property copyright "Market Dashboard"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include "MarketEngines/MarketTimeEngine.mqh"

//--- 入力パラメータ (座標は不要。ドラッグで移動可能)
input bool   ShowEventLines = true;  // (将来的な拡張用) チャートに経済指標の縦線を表示する
input color  ColorHigh      = clrRed; // 重要指標の線の色

//--- グローバル変数 (パネル位置管理)
string g_panelName = "MD_Panel_BG";
int    g_panelX = 10;
int    g_panelY = 10;

//+------------------------------------------------------------------+
int OnInit()
{
   if(!MTE_Init())
     {
      Print("MarketTimeEngine 初期化失敗");
      return(INIT_FAILED);
     }

   // 前回の位置を復元
   if(GlobalVariableCheck("MD_Panel_X")) g_panelX = (int)GlobalVariableGet("MD_Panel_X");
   if(GlobalVariableCheck("MD_Panel_Y")) g_panelY = (int)GlobalVariableGet("MD_Panel_Y");

   // パネル背景の作成 (ドラッグ可能)
   CreatePanelBackground();
   
   // テキスト要素の作成
   CreatePanelTexts();

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   MTE_Deinit();
   
   // オブジェクトの削除
   ObjectsDeleteAll(0, "MD_");
   
   // 最終位置の保存
   if(ObjectFind(0, g_panelName) >= 0)
     {
      GlobalVariableSet("MD_Panel_X", ObjectGetInteger(0, g_panelName, OBJPROP_XDISTANCE));
      GlobalVariableSet("MD_Panel_Y", ObjectGetInteger(0, g_panelName, OBJPROP_YDISTANCE));
     }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   return(rates_total);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   MTE_Update();
   UpdatePanelTexts();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // パネル背景がクリックされた時の処理（ドラッグ可能にする）
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == g_panelName)
     {
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTED, true);
      ChartRedraw(0);
      return;
     }

   // パネル背景がドラッグされた時の処理
   if(id == CHARTEVENT_OBJECT_DRAG && sparam == g_panelName)
     {
      long newX = ObjectGetInteger(0, g_panelName, OBJPROP_XDISTANCE);
      long newY = ObjectGetInteger(0, g_panelName, OBJPROP_YDISTANCE);
      
      // 関連するテキストオブジェクトも連動して移動させる
      MoveObject("MD_Title", newX + 5, newY + 5);
      MoveObject("MD_Market", newX + 5, newY + 25);
      MoveObject("MD_Event", newX + 5, newY + 85);
      
      // 位置情報を保存
      GlobalVariableSet("MD_Panel_X", newX);
      GlobalVariableSet("MD_Panel_Y", newY);
      
      // ドラッグ終了時に選択状態を解除（点線枠を消す）
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTED, false);
      
      ChartRedraw(0);
     }
}

//+------------------------------------------------------------------+
//| パネル背景作成                                                   |
//+------------------------------------------------------------------+
void CreatePanelBackground()
{
   if(ObjectFind(0, g_panelName) < 0)
     {
      ObjectCreate(0, g_panelName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, g_panelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, g_panelName, OBJPROP_XDISTANCE, g_panelX);
      ObjectSetInteger(0, g_panelName, OBJPROP_YDISTANCE, g_panelY);
      ObjectSetInteger(0, g_panelName, OBJPROP_XSIZE, 250);
      ObjectSetInteger(0, g_panelName, OBJPROP_YSIZE, 110);
      ObjectSetInteger(0, g_panelName, OBJPROP_BGCOLOR, clrDarkSlateGray);
      ObjectSetInteger(0, g_panelName, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, g_panelName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, g_panelName, OBJPROP_WIDTH, 2);
      
      // ★ドラッグ可能にする重要な設定★
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, g_panelName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, g_panelName, OBJPROP_BACK, true);
     }
}

//+------------------------------------------------------------------+
//| テキスト要素の作成                                               |
//+------------------------------------------------------------------+
void CreatePanelTexts()
{
   CreateTextLabel("MD_Title", g_panelX + 5, g_panelY + 5, "", clrWhite, 9);
   CreateTextLabel("MD_Market", g_panelX + 5, g_panelY + 25, "", clrWhite, 8);
   CreateTextLabel("MD_Event", g_panelX + 5, g_panelY + 85, "", clrYellow, 8);
}

//+------------------------------------------------------------------+
//| テキスト更新                                                     |
//+------------------------------------------------------------------+
void UpdatePanelTexts()
{
   string title = MTE_GetJSTText();
   ObjectSetString(0, "MD_Title", OBJPROP_TEXT, title);

   string marketInfo = "";
   marketInfo += StringFormat("東京   : %s %s\n", MTE_GetMarketStatusIcon(g_tokyo.status), g_tokyo.timeText);
   marketInfo += StringFormat("ロンドン: %s %s\n", MTE_GetMarketStatusIcon(g_london.status), g_london.timeText);
   marketInfo += StringFormat("NY     : %s %s", MTE_GetMarketStatusIcon(g_ny.status), g_ny.timeText);
   ObjectSetString(0, "MD_Market", OBJPROP_TEXT, marketInfo);

   string eventInfo = "【次の指標】\n" + MTE_GetNextEventText();
   ObjectSetString(0, "MD_Event", OBJPROP_TEXT, eventInfo);
}

//+------------------------------------------------------------------+
//| ユーティリティ: テキストラベル作成                               |
//+------------------------------------------------------------------+
void CreateTextLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false); // テキスト自体はドラッグ不可
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| ユーティリティ: オブジェクト移動                                 |
//+------------------------------------------------------------------+
void MoveObject(string name, long x, long y)
{
   if(ObjectFind(0, name) >= 0)
     {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
     }
}
//+------------------------------------------------------------------+
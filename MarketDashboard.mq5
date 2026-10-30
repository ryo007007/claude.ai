//+------------------------------------------------------------------+
//|                                              MarketDashboard.mq5 |
//| 市場時間・経済指標ダッシュボード (マウスドラッグ移動対応)        |
//+------------------------------------------------------------------+
#property copyright "Market Dashboard"
#property version   "1.04"
#property indicator_chart_window
#property indicator_plots 0

#include "MarketEngines/MarketTimeEngine.mqh"

//--- 入力パラメータ
input bool   ShowEventLines = true;  // (将来的な拡張用) チャートに経済指標の縦線を表示する
input color  ColorHigh      = clrRed; // 重要指標の線の色

//--- グローバル変数 (パネル位置・ドラッグ管理)
string   g_panelName        = "MD_Panel_BG";
int      g_panelX           = 10;
int      g_panelY           = 10;
bool     g_isDragging       = false;
int      g_dragStartMouseX  = 0;
int      g_dragStartMouseY  = 0;
int      g_dragStartPanelX  = 0;
int      g_dragStartPanelY  = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
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

   // マウス移動イベントを有効化
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   // パネル背景の作成
   CreatePanelBackground();
   
   // テキスト要素の作成
   CreatePanelTexts();

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   MTE_Deinit();
   
   // 万が一ドラッグ中にインジケーターが削除された場合を考慮し、念のためスクロールを有効に戻しておく
   ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
   
   // オブジェクトの削除 (接頭辞 "MD_" で一括削除)
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
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   MTE_Update();
   UpdatePanelTexts();
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // マウス移動イベントでドラッグ処理
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int x = (int)lparam;      // チャート上のXピクセル座標
      int y = (int)dparam;      // チャート上のYピクセル座標
      int state = (int)sparam;  // マウスボタン状態（bit0=左、bit1=右、bit2=中）
      bool leftDown = (state & 1) == 1;
      
      if(g_isDragging)
        {
         if(leftDown)
           {
            // ドラッグ中：パネル位置を更新
            int newX = g_dragStartPanelX + (x - g_dragStartMouseX);
            int newY = g_dragStartPanelY + (y - g_dragStartMouseY);
            
            // 画面外に出ないよう制限
            if(newX < 0) newX = 0;
            if(newY < 0) newY = 0;
            
            // パネル背景を移動
            ObjectSetInteger(0, g_panelName, OBJPROP_XDISTANCE, newX);
            ObjectSetInteger(0, g_panelName, OBJPROP_YDISTANCE, newY);
            
            // テキストラベルも連動移動（市場ごとの各ラベルに対応）
            MoveObject("MD_Title",  newX + 5, newY + 5);
            MoveObject("MD_Tokyo",  newX + 5, newY + 25);
            MoveObject("MD_London", newX + 5, newY + 40);
            MoveObject("MD_NY",     newX + 5, newY + 55);
            MoveObject("MD_Event",  newX + 5, newY + 85);
            
            ChartRedraw(0);
           }
         else
           {
            // 左ボタンが離された → ドラッグ終了、位置を保存
            g_isDragging = false;
            
            // ★ チャートスクロールを再有効化
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            
            long finalX = ObjectGetInteger(0, g_panelName, OBJPROP_XDISTANCE);
            long finalY = ObjectGetInteger(0, g_panelName, OBJPROP_YDISTANCE);
            GlobalVariableSet("MD_Panel_X", finalX);
            GlobalVariableSet("MD_Panel_Y", finalY);
           }
         return;
        }
      
      // パネル上で左クリック開始か確認
      if(leftDown && !g_isDragging)
        {
         long px = ObjectGetInteger(0, g_panelName, OBJPROP_XDISTANCE);
         long py = ObjectGetInteger(0, g_panelName, OBJPROP_YDISTANCE);
         long pw = ObjectGetInteger(0, g_panelName, OBJPROP_XSIZE);
         long ph = ObjectGetInteger(0, g_panelName, OBJPROP_YSIZE);
         
         // マウスがパネル矩形内にあるか
         if(x >= px && x < px + pw && y >= py && y < py + ph)
           {
            g_isDragging = true;
            g_dragStartMouseX = x;
            g_dragStartMouseY = y;
            g_dragStartPanelX = (int)px;
            g_dragStartPanelY = (int)py;
            
            // ★ チャートスクロールを一時無効化（パネルドラッグ中）
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
           }
        }
      return;
     }
}

//+------------------------------------------------------------------+
//| パネル背景作成                                                   |
//+------------------------------------------------------------------+
void CreatePanelBackground()
{
   if(ObjectFind(0, g_panelName) < 0)
     {
      // OBJ_RECTANGLE_LABEL を使用
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
      
      // ドラッグ不要なので SELECTABLE は false
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, g_panelName, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, g_panelName, OBJPROP_HIDDEN, false);
      ObjectSetInteger(0, g_panelName, OBJPROP_BACK, true);
      
      // ZORDER を下げてラベルが上に来るようにする
      ObjectSetInteger(0, g_panelName, OBJPROP_ZORDER, 1);
     }
}

//+------------------------------------------------------------------+
//| テキスト要素の作成                                               |
//+------------------------------------------------------------------+
void CreatePanelTexts()
{
   CreateTextLabel("MD_Title",  g_panelX + 5, g_panelY + 5,  "", clrWhite, 9);
   
   // MD_Market を3行に分離（OBJ_LABEL は改行非対応）
   CreateTextLabel("MD_Tokyo",  g_panelX + 5, g_panelY + 25, "", clrWhite, 8);
   CreateTextLabel("MD_London", g_panelX + 5, g_panelY + 40, "", clrWhite, 8);
   CreateTextLabel("MD_NY",     g_panelX + 5, g_panelY + 55, "", clrWhite, 8);
   
   CreateTextLabel("MD_Event",  g_panelX + 5, g_panelY + 85, "", clrYellow, 8);
}

//+------------------------------------------------------------------+
//| テキスト更新                                                     |
//+------------------------------------------------------------------+
void UpdatePanelTexts()
{
   string title = MTE_GetJSTText();
   ObjectSetString(0, "MD_Title", OBJPROP_TEXT, title);

   // 各行を個別のラベルに設定
   ObjectSetString(0, "MD_Tokyo", OBJPROP_TEXT, 
      StringFormat("東京   : %s %s", MTE_GetMarketStatusIcon(g_tokyo.status), g_tokyo.timeText));
   ObjectSetString(0, "MD_London", OBJPROP_TEXT, 
      StringFormat("ロンドン: %s %s", MTE_GetMarketStatusIcon(g_london.status), g_london.timeText));
   ObjectSetString(0, "MD_NY", OBJPROP_TEXT, 
      StringFormat("NY     : %s %s", MTE_GetMarketStatusIcon(g_ny.status), g_ny.timeText));

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
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      
      // ZORDER を背景より上にする
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
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
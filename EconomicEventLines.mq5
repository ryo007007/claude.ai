//+------------------------------------------------------------------+
//|                                        EconomicEventLines.mq5     |
//|  経済指標の縦の破線(未来方向)+ 日本時間の指標リスト               |
//|                                                                    |
//|  ・重要度「高」の指標                 → 赤の破線                  |
//|  ・重要でなくても前回大きく動いた指標 → その他の色の破線          |
//|  ・重要でもなく前回も動いていない指標 → 表示しない                |
//|                                                                    |
//|  判定・データ取得は MarketEngines/EventImpactEngine.mqh が行う。   |
//|  CCompression_Scanner と同じチャートに入れておくと、スキャナーの   |
//|  行をクリックして通貨ペアが切り替わった時に、その通貨ペアの指標線に |
//|  自動で切り替わる。                                                |
//|                                                                    |
//|  ※チャートの右側に余白(チャート設定の「チャートの右端をシフト」)を |
//|    取ると、未来の指標線が見える。                                  |
//+------------------------------------------------------------------+
#property copyright "economic event lines"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

#include "MarketEngines/EventImpactEngine.mqh"

input group "=== 表示 ==="
input bool   EVL_ShowLines   = true;        // 起動時に縦線を表示する(ボタンで切替可)
input bool   EVL_ShowList    = true;        // 起動時に日本時間の指標リストを表示する(ボタンで切替可)
input color  EVL_ColorHigh   = clrRed;      // 重要指標の線の色
input color  EVL_ColorOther  = clrOrange;   // その他(前回大きく動いた指標)の線の色
input ENUM_LINE_STYLE EVL_Style = STYLE_DASH; // 線の種類
input int    EVL_Width       = 1;           // 線の太さ
input ENUM_LINE_STYLE EVL_PastStyle = STYLE_DOT; // 過去の指標の線の種類
input bool   EVL_ShowLabels  = true;        // 線の横に指標名を表示する

input group "=== 指標リスト・ボタンの位置 ==="
input ENUM_BASE_CORNER EVL_ListCorner = CORNER_RIGHT_LOWER; // リストを表示する隅
input int    EVL_ListX       = 10;          // 隅からのX距離
input int    EVL_ListY       = 60;          // 隅からのY距離(ボタンの上に表示)
input int    EVL_ListMax     = 6;           // リストに表示する件数
input int    EVL_BtnX        = 10;          // ボタンのX距離(隅からの距離)
input int    EVL_BtnY        = 30;          // ボタンのY距離

//--- 画面のON/OFF状態(ボタンで切替。チャート切替でも引き継ぐ)
bool g_linesOn = true;
bool g_listOn  = true;
int  g_listLineCount = 0;

//--- 時刻ごとにまとめた指標(同時刻の複数指標は1本の線にまとめる)
datetime gTime[];
int      gCls[];
int      gCnt[];
string   gText[];
string   gTip[];
double   gAct[];      // その時刻の指標の「今回の動き」(ATR倍。過去の指標のみ。-1=なし)

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!EVI_Init(_Symbol))
      Print("EconomicEventLines: 初期化に失敗しました");

   g_linesOn = GlobalVariableCheck("EVL_UI_LINES") ? (GlobalVariableGet("EVL_UI_LINES") > 0.5) : EVL_ShowLines;
   g_listOn  = GlobalVariableCheck("EVL_UI_LIST")  ? (GlobalVariableGet("EVL_UI_LIST")  > 0.5) : EVL_ShowList;

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   EVI_Deinit();
   ObjectsDeleteAll(0, "EVL_");
   ChartRedraw(0);
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   return(rates_total);
  }

void OnTimer()
  {
   EVI_Refresh();
   Redraw();
  }

//+------------------------------------------------------------------+
//| 指標名を短くする                                                   |
//+------------------------------------------------------------------+
string ShortName(const string name)
  {
   if(StringLen(name) <= 26) return name;
   return StringSubstr(name, 0, 25) + "…";
  }

//+------------------------------------------------------------------+
//| 表示対象の指標を、時刻ごとにまとめる                               |
//+------------------------------------------------------------------+
void BuildGroups()
  {
   ArrayResize(gTime, 0);
   ArrayResize(gCls, 0);
   ArrayResize(gCnt, 0);
   ArrayResize(gText, 0);
   ArrayResize(gTip, 0);
   ArrayResize(gAct, 0);

   int n = EVI_Count();
   for(int i = 0; i < n; i++)
     {
      int cls = EVI_Class(i);
      if(cls == 0)
         continue;

      datetime t = EVI_DrawTime(g_eviTime[i]);
      string nm = StringFormat("[%s] %s%s", g_eviCur[i], ShortName(g_eviName[i]), cls == 2 ? " ★" : " ◆");

      double last = EVI_LastRatio(i);
      double avg  = EVI_AvgRatio(i);
      string mv = (last >= 0.0)
         ? StringFormat("前回の動き %.1fATR(直近%d回平均 %.1fATR)", last, EVI_ValidN(i), avg)
         : "前回の動き: 算出できません(履歴不足など)";
      double act = EVI_ActualRatio(i);
      if(act >= 0.0)
         mv += StringFormat(" / 今回の動き %.1fATR", act);
      string tip = StringFormat("%s  [%s] %s  重要度:%s  %s",
                                EVI_JstText(t), g_eviCur[i], g_eviName[i], EVI_ImpText(g_eviImp[i]), mv);

      int g = ArraySize(gTime);
      if(g > 0 && gTime[g - 1] == t)
        {
         gCls[g - 1] = MathMax(gCls[g - 1], cls);
         gAct[g - 1] = MathMax(gAct[g - 1], act);
         gCnt[g - 1]++;
         if(gCnt[g - 1] <= 2)
            gText[g - 1] += " / " + nm;
         gTip[g - 1] += "\n" + tip;
        }
      else
        {
         ArrayResize(gTime, g + 1);
         ArrayResize(gCls,  g + 1);
         ArrayResize(gCnt,  g + 1);
         ArrayResize(gText, g + 1);
         ArrayResize(gTip,  g + 1);
         ArrayResize(gAct,  g + 1);
         gTime[g] = t;
         gCls[g]  = cls;
         gCnt[g]  = 1;
         gText[g] = nm;
         gTip[g]  = tip;
         gAct[g]  = act;
        }
     }
  }

//+------------------------------------------------------------------+
//| 縦線・ラベルの描画                                                 |
//+------------------------------------------------------------------+
void DrawLines()
  {
   string cur[];   // 今回描画したオブジェクト名(これ以外の古い線は削除する)
   datetime nowS = TimeTradeServer();

   double pmin = ChartGetDouble(0, CHART_PRICE_MIN);
   double pmax = ChartGetDouble(0, CHART_PRICE_MAX);
   double yLabel = pmin + (pmax - pmin) * 0.03;

   int ng = ArraySize(gTime);
   for(int g = 0; g < ng; g++)
     {
      string ln = "EVL_L_" + IntegerToString((long)gTime[g]);
      string tn = "EVL_T_" + IntegerToString((long)gTime[g]);
      color  clr = (gCls[g] == 2) ? EVL_ColorHigh : EVL_ColorOther;
      ENUM_LINE_STYLE st = (gTime[g] < nowS) ? EVL_PastStyle : EVL_Style;   // 過去の指標は別の線種

      if(ObjectFind(0, ln) < 0)
        {
         ObjectCreate(0, ln, OBJ_VLINE, 0, gTime[g], 0);
         ObjectSetInteger(0, ln, OBJPROP_BACK, true);
         ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, ln, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, ln, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
        }
      ObjectSetInteger(0, ln, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, ln, OBJPROP_STYLE, st);
      ObjectSetInteger(0, ln, OBJPROP_WIDTH, EVL_Width);
      ObjectSetString(0, ln, OBJPROP_TOOLTIP, gTip[g]);

      int k = ArraySize(cur);
      ArrayResize(cur, k + 1);
      cur[k] = ln;

      if(EVL_ShowLabels)
        {
         string txt = EVI_JstText(gTime[g]) + " " + gText[g];
         if(gCnt[g] > 2)
            txt += StringFormat(" 他%d件", gCnt[g] - 2);
         // 過去の指標は、実際にどれだけ動いたか(ATR倍)を付ける。判定(色)との答え合わせ用
         if(gTime[g] < nowS && gAct[g] >= 0.0)
            txt += StringFormat(" → %.1fATR", gAct[g]);

         if(ObjectFind(0, tn) < 0)
           {
            ObjectCreate(0, tn, OBJ_TEXT, 0, gTime[g], yLabel);
            ObjectSetInteger(0, tn, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, tn, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, tn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
            ObjectSetInteger(0, tn, OBJPROP_FONTSIZE, 8);
            ObjectSetString(0, tn, OBJPROP_FONT, "Meiryo");
            ObjectSetDouble(0, tn, OBJPROP_ANGLE, 90.0);   // 縦書き(下から上へ)
           }
         ObjectSetInteger(0, tn, OBJPROP_TIME, gTime[g]);
         ObjectSetDouble(0, tn, OBJPROP_PRICE, yLabel);   // 価格軸の表示範囲が変わっても下端に追従
         ObjectSetString(0, tn, OBJPROP_TEXT, txt);
         ObjectSetInteger(0, tn, OBJPROP_COLOR, clr);

         k = ArraySize(cur);
         ArrayResize(cur, k + 1);
         cur[k] = tn;
        }
     }

   //--- 今回の対象外になった古い線・ラベルを削除 ---
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "EVL_L_") != 0 && StringFind(name, "EVL_T_") != 0)
         continue;
      bool keep = false;
      for(int j = 0; j < ArraySize(cur); j++)
         if(cur[j] == name) { keep = true; break; }
      if(!keep)
         ObjectDelete(0, name);
     }
  }

void ClearLines()
  {
   ObjectsDeleteAll(0, "EVL_L_");
   ObjectsDeleteAll(0, "EVL_T_");
  }

//+------------------------------------------------------------------+
//| 日本時間の指標リスト                                               |
//+------------------------------------------------------------------+
void SetListLine(const int j, const int total, const string text, const color clr)
  {
   string name = "EVL_List_" + IntegerToString(j);
   bool lower = (EVL_ListCorner == CORNER_LEFT_LOWER  || EVL_ListCorner == CORNER_RIGHT_LOWER);
   bool right = (EVL_ListCorner == CORNER_RIGHT_UPPER || EVL_ListCorner == CORNER_RIGHT_LOWER);

   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Meiryo");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
     }

   ENUM_ANCHOR_POINT anchor;
   if(lower) anchor = right ? ANCHOR_RIGHT_LOWER : ANCHOR_LEFT_LOWER;
   else      anchor = right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER;

   int lineH = 16;
   int y = lower ? EVL_ListY + (total - 1 - j) * lineH : EVL_ListY + j * lineH;

   ObjectSetInteger(0, name, OBJPROP_CORNER, EVL_ListCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, EVL_ListX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void DrawList()
  {
   datetime nowS = TimeTradeServer();

   string lines[];
   color  clrs[];
   int L = 0;
   ArrayResize(lines, EVL_ListMax + 2);
   ArrayResize(clrs,  EVL_ListMax + 2);

   lines[L] = StringFormat("今後の指標(日本時間) %s  [影響度の評価 %d/%d]",
                           _Symbol, g_eviEvaluated, EVI_Count());
   if(!g_eviOk)
      lines[L] = StringFormat("今後の指標(日本時間) %s  [%s]", _Symbol, EVI_StatusText());
   clrs[L] = clrWhite;
   L++;

   int shown = 0;
   int ng = ArraySize(gTime);
   for(int g = 0; g < ng && shown < EVL_ListMax; g++)
     {
      if(gTime[g] < nowS - 60)
         continue;   // 発表済みはリストに出さない
      int mins = (int)((gTime[g] - nowS) / 60);
      if(mins < 0) mins = 0;
      string left = (mins >= 60) ? StringFormat("あと%d時間%02d分", mins / 60, mins % 60)
                                 : StringFormat("あと%d分", mins);
      string txt = StringFormat("%s (%s) %s", EVI_JstText(gTime[g]), left, gText[g]);
      if(gCnt[g] > 2)
         txt += StringFormat(" 他%d件", gCnt[g] - 2);
      lines[L] = txt;
      clrs[L]  = (gCls[g] == 2) ? EVL_ColorHigh : EVL_ColorOther;
      L++;
      shown++;
     }
   if(shown == 0 && g_eviOk)
     {
      lines[L] = "  (表示対象の指標はありません)";
      clrs[L]  = clrGray;
      L++;
     }

   for(int j = 0; j < L; j++)
      SetListLine(j, L, lines[j], clrs[j]);

   for(int j = L; j < g_listLineCount; j++)
      ObjectDelete(0, "EVL_List_" + IntegerToString(j));
   g_listLineCount = L;
  }

void ClearList()
  {
   ObjectsDeleteAll(0, "EVL_List_");
   g_listLineCount = 0;
  }

//+------------------------------------------------------------------+
//| ON/OFFボタン                                                       |
//+------------------------------------------------------------------+
void DrawButton(const string name, const int x, const string text, const color bg)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 128);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER, EVL_ListCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, EVL_BtnY);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
  }

void DrawButtons()
  {
   DrawButton("EVL_BtnLines", EVL_BtnX,
              g_linesOn ? "指標ライン: 表示" : "指標ライン: 非表示",
              g_linesOn ? C'40,90,40' : C'70,70,70');
   DrawButton("EVL_BtnList", EVL_BtnX + 132,
              g_listOn ? "指標リスト: 表示" : "指標リスト: 非表示",
              g_listOn ? C'40,90,40' : C'70,70,70');
  }

//+------------------------------------------------------------------+
//| 全体の再描画(1秒ごと)                                            |
//+------------------------------------------------------------------+
void Redraw()
  {
   BuildGroups();

   if(g_linesOn) DrawLines(); else ClearLines();
   if(g_listOn)  DrawList();  else ClearList();
   DrawButtons();

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == "EVL_BtnLines")
     {
      g_linesOn = !g_linesOn;
      GlobalVariableSet("EVL_UI_LINES", g_linesOn ? 1.0 : 0.0);
      Redraw();
     }
   else if(sparam == "EVL_BtnList")
     {
      g_listOn = !g_listOn;
      GlobalVariableSet("EVL_UI_LIST", g_listOn ? 1.0 : 0.0);
      Redraw();
     }
  }
//+------------------------------------------------------------------+

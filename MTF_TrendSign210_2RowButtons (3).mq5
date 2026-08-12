//+------------------------------------------------------------------+
//|                                           MTF_TrendSing210.mq5 |
//| 複数通貨ペアを同時に監視するマルチタイムフレーム・トレンド判定    |
//| ダッシュボード。手動2点指定＆辺選択連鎖増殖ペンタゴン機能搭載。  |
//+------------------------------------------------------------------+
#property copyright "Custom MTF Trend Sign 210 (Interactive Pentagon)"
#property version   "5.10"
#property indicator_chart_window
#property indicator_buffers 13
#property indicator_plots   13

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3
#property indicator_label1  "BuySignal"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3
#property indicator_label2  "SellSignal"

#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  2
#property indicator_label3  "Weekly Fast EMA"

#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrange
#property indicator_width4  1
#property indicator_label4  "Weekly Slow EMA"

#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_width5  2
#property indicator_label5  "Upper Fast EMA"

#property indicator_type6   DRAW_LINE
#property indicator_color6  clrMaroon
#property indicator_width6  1
#property indicator_label6  "Upper Slow EMA"

#property indicator_type7   DRAW_LINE
#property indicator_color7  clrLime
#property indicator_width7  2
#property indicator_label7  "Middle Fast EMA"

#property indicator_type8   DRAW_LINE
#property indicator_color8  clrGreen
#property indicator_width8  1
#property indicator_label8  "Middle Slow EMA"

#property indicator_type9   DRAW_LINE
#property indicator_color9  clrDodgerBlue
#property indicator_width9  2
#property indicator_label9  "Lower Fast EMA"

#property indicator_type10  DRAW_LINE
#property indicator_color10 clrBlue
#property indicator_width10 1
#property indicator_label10 "Lower Slow EMA"

#property indicator_type11  DRAW_LINE
#property indicator_color11 clrAqua
#property indicator_width11 1
#property indicator_label11 "BB Upper"

#property indicator_type12  DRAW_LINE
#property indicator_color12 clrSilver
#property indicator_style12 STYLE_DOT
#property indicator_label12 "BB Middle"

#property indicator_type13  DRAW_LINE
#property indicator_color13 clrAqua
#property indicator_width13 1
#property indicator_label13 "BB Lower"

//---------------- 入力パラメータ ----------------
input string InpSymbols = "USDJPY,EURUSD,GBPUSD,AUDUSD,NZDUSD,USDCAD,USDCHF,EURJPY,GBPJPY,AUDJPY,NZDJPY,CADJPY,CHFJPY,EURGBP,GBPCHF,EURCAD,EURCHF,AUDNZD,CADCHF,AUDCHF,GBPCAD,AUDCAD,EURAUD,GBPAUD,EURNZD,XAUUSD,BTCUSD"; 

input ENUM_TIMEFRAMES TF_Weekly   = PERIOD_W1;   // 週足
input ENUM_TIMEFRAMES TF_Upper    = PERIOD_M15;  // 上位足（15分足）
input ENUM_TIMEFRAMES TF_Middle   = PERIOD_M5;   // 中位足（5分足）
input ENUM_TIMEFRAMES TF_Lower    = PERIOD_M1;   // 下位足（1分足）

input int    EMA_Fast_Period = 4;    // 短期EMA期間
input int    EMA_Slow_Period = 8;    // 長期EMA期間
input int    Slope_Lookback  = 2;    // 傾き判定に使う本数（Nバー前と比較）

//---------------- ボリンジャーバンド設定 ----------------
input int    Bands_Period    = 200;  // ボリンジャーバンド期間
input double Bands_Dev       = 2.0;  // ボリンジャーバンド偏差(σ)
input bool   Show_BB_Default = true; // ボリンジャーバンドを最初から表示するか

//---------------- 200BB外の強調フィルター設定 ----------------
input double BB_Filter_Dev   = 2.0;        // 日足・週足200BBの超過判定σ値
input color  PanelExceedColor = clrMagenta; // 200BB外にある通貨ペアの強調カラー

//---------------- トレンド判定用EMA線をチャートに表示 ----------------
input bool Show_Weekly_Default = true;   
input bool Show_Upper_Default  = true;   
input bool Show_Middle_Default = true;   
input bool Show_Lower_Default  = true;   
input int  MaxHighTFBars = 3000;  

//---------------- Pivot設定 ----------------
input bool  Show_DP_Default  = true;     // 日足Pivot(DP)初期状態
input bool  Show_WP_Default  = true;     // 週足Pivot(WP)初期状態
input color PivotPColor      = clrGold;   // Pivot (P) ラインの色
input color PivotRColor      = clrRed;    // Resistance (R1, R2) の色
input color PivotSColor      = clrLime;   // Support (S1, S2) の色
input int   PivotHistoryDays = 30;       // 日足Pivot過去描画日数
input int   PivotHistoryWeeks= 12;       // 週足Pivot過去描画週数

//---------------- ペンタゴン設定 ----------------
input color  PentagonColor = clrGold; // ペンタゴンの線カラー
input int    PentagonWidth = 2;       // ペンタゴンの線幅

//---------------- 通貨強弱インジケーター設定 ----------------
input bool            UseCurrencyStrength = true;      // 通貨強弱の色付け・ランキングを使うか
input ENUM_TIMEFRAMES StrengthTF = PERIOD_M1;           // 強弱判定に使う時間足（直近確定足の上昇/下降）
input color           StrengthTopColor    = clrRed;     // 最強通貨の色
input color           StrengthBottomColor = clrDodgerBlue; // 最弱通貨の色
input double          CurrencyCharWidthPx = 6.6;        // 1文字あたりの推定ピクセル幅（ズレる場合は調整）
input bool            ShowCurrencyRanking = true;       // 右下に通貨強弱ランキングを表示するか
input int             RankingPanel_X = 15;              // ランキングパネルのX座標（右下基準）
input int             RankingPanel_Y = 80;              // ランキングパネルのY座標（右下基準）

//---------------- 直近高値・安値 接近アラート設定 ----------------
input bool   UseHighLowAlert = true;         // 過去N時間の高値/安値への接近をチェックするか
input int    HighLowLookbackHours = 120;     // 何時間分（5営業日=120時間）を見るか
input double HighLowProximityPips = 10.0;    // 高値/安値からこのpips以内に近づいたらサイン
input int    HighLowAlertCooldownMin = 60;   // 同じ通貨ペアで再アラートするまでの最短間隔(分)

//---------------- パネル＆レイアウト設定 ----------------
input bool  UsePanel        = true;  
input ENUM_BASE_CORNER PanelCorner = CORNER_RIGHT_UPPER; 

input bool UseMAButtons = true; // ボタンを表示するか
input int  MAButton_X  = 15;   // X座標（右下基準）
input int  MAButton_Y  = 15;   // Y座標（右下基準）

input bool  UseAlert        = true;  // ポップアップアラート全体のON/OFF（マスタースイッチ）
input bool  UsePush         = true;  // プッシュ通知全体のON/OFF（マスタースイッチ）

//---------------- アラート種別ごとの個別ON/OFF ----------------
// UseAlert/UsePushがONの場合でも、ここがOFFならその種類のアラートだけ鳴らさない
input bool AlertOnTrendSignal = true; // 週波/大波/中波/小波の売買シグナルアラート
input bool AlertOnSqueeze     = true; // 値幅スクイーズ（ブレイク前兆）アラート
input bool AlertOnHighLow     = true; // 直近高値/安値接近アラート

input color PanelUpColor    = clrDodgerBlue;
input color PanelDownColor  = clrRed;
input color PanelFlatColor  = clrSilver;

input bool  ResetCountsOnLoad = false; 
input int   DailyResetHour = 0; 
input bool  UseDailyReset = true; 

input bool  OpenInNewChart = false; 

//---------------- バッファ ----------------
double BuySignalBuffer[];
double SellSignalBuffer[];
double WeeklyFastBuffer[];
double WeeklySlowBuffer[];
double UpperFastBuffer[];
double UpperSlowBuffer[];
double MiddleFastBuffer[];
double MiddleSlowBuffer[];
double LowerFastBuffer[];
double LowerSlowBuffer[];
double BBUpperBuffer[];
double BBMiddleBuffer[];
double BBLowerBuffer[];

//---------------- 通貨ペアごとの変数 ----------------
string g_symbols[];
int    g_symbolCount = 0;
int    g_currentSymbolIndex = -1;

int g_hWeeklyFast[],  g_hWeeklySlow[];
int g_hUpperFast[],   g_hUpperSlow[];
int g_hMiddleFast[],  g_hMiddleSlow[];
int g_hLowerFast[],   g_hLowerSlow[];

int g_hBB_Daily[];
int g_hBB_Weekly[];
int g_hBB_H4[];
int g_hBB = INVALID_HANDLE;

datetime lastAlertBarTime[]; // 通貨ペアごとのシグナルアラート重複防止（配列化）

int      g_signalCount[];
int      g_signalCountNoWeekly[]; 
datetime g_lastSignalBarTime[];
datetime g_lastSignalBarTimeNoWeekly[];
bool     g_useWeeklyFilterPerSymbol[]; 

datetime g_lastResetBoundary = 0;
bool     g_maLinesFilled = false;
bool     g_pivotDPReady = false; // 日足Pivotの描画に必要なデータが揃ったか
bool     g_pivotWPReady = false; // 週足Pivotの描画に必要なデータが揃ったか

bool g_showWeekly   = true;
bool g_showUpper    = true;
bool g_showMiddle   = true;
bool g_showLower    = true;
bool g_showBB       = true;
bool g_showDP       = true;
bool g_showWP       = true;
bool g_hideAllPanel = false; // 通貨ペアパネルの一括非表示フラグ

// アラートの重複防止用
datetime g_lastDPSqueezeAlertTime[]; // 通貨ペアごとのスクイーズアラート重複防止（配列化）
datetime g_lastWPSqueezeAlertTime[];

//---------------- 通貨強弱インジケーター用変数 ----------------
#define MAJOR_COUNT 7
string g_majors[MAJOR_COUNT] = {"USD","EUR","JPY","GBP","CHF","AUD","CAD"};
double g_currencyScore[MAJOR_COUNT];
int    g_currencyRank[MAJOR_COUNT];   // 1=最強 ... 7=最弱
color  g_currencyColor[MAJOR_COUNT];
string g_bestPairSymbol = ""; // 最強/最弱ペアが実際にFX会社で提供している銘柄名（クリック用）

//---------------- 高値/安値接近アラート用変数 ----------------
datetime g_lastHLAlertTime[];

//---------------- インタラクティブ・ペンタゴン用変数 ----------------
bool     g_showPentagon   = false; 
int      g_pentaClickStep = 0;     
datetime g_p1_time = 0, g_p2_time = 0;
double   g_p1_price = 0.0, g_p2_price = 0.0;
int      g_pentagonCounter = 0;    
uint     g_lastBtnClickTick = 0;   

#define BTN_BB       "MTF_Btn_BB"
#define BTN_WP       "MTF_Btn_WP"
#define BTN_DP       "MTF_Btn_DP"
#define BTN_WEEKLY   "MTF_Btn_Weekly"
#define BTN_UPPER    "MTF_Btn_Upper"
#define BTN_MIDDLE   "MTF_Btn_Middle"
#define BTN_LOWER    "MTF_Btn_Lower"
#define BTN_PENTAGON "MTF_Btn_Pentagon" 
#define BTN_HIDE     "MTF_Btn_Hide"

#define PIVOT_DP_PREFIX "MTF_Pivot_DP_"
#define PIVOT_WP_PREFIX "MTF_Pivot_WP_"

#define BTN_W_FILTER_PREFIX  "MTF_W_Btn_"
#define PENTAGON_OBJ_PREFIX  "MTF_PentaObj_"
#define PENTAGON_EDGE_PREFIX "MTF_PentaEdge_"
#define PENTAGON_GUIDE_LINE  "MTF_PentaGuideLine"

#define GVAR_PREFIX     "MTF210_Cnt_"
#define GVAR_PREFIX_NOW "MTF210_CntNoW_"
#define GVAR_PREFIX_WF  "MTF210_WF_"

string CountVarName(string sym) { return GVAR_PREFIX + sym; }
string CountNoWeeklyVarName(string sym) { return GVAR_PREFIX_NOW + sym; }
string WeeklyFilterVarName(string sym) { return GVAR_PREFIX_WF + sym; }

datetime GetCurrentResetBoundary()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   dt.hour = DailyResetHour; dt.min = 0; dt.sec = 0;
   datetime boundaryToday = StructToTime(dt);
   if(now < boundaryToday) boundaryToday -= 86400;
   return boundaryToday;
}

void ResetAllSignalCounts()
{
   for(int i = 0; i < g_symbolCount; i++)
   {
      g_signalCount[i] = 0;
      GlobalVariableSet(CountVarName(g_symbols[i]), 0);
      g_signalCountNoWeekly[i] = 0;
      GlobalVariableSet(CountNoWeeklyVarName(g_symbols[i]), 0);
   }
}

int ParseSymbols(string src, string &outArr[])
{
   string raw[];
   int n = StringSplit(src, ',', raw);
   int count = 0;
   ArrayResize(outArr, n);
   for(int i = 0; i < n; i++)
   {
      string s = raw[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s) == 0) continue;
      outArr[count] = s;
      count++;
   }
   ArrayResize(outArr, count);

   for(int a = 0; a < count - 1; a++)
   {
      int minIdx = a;
      for(int b = a + 1; b < count; b++)
         if(outArr[b] < outArr[minIdx]) minIdx = b;
      if(minIdx != a)
      {
         string tmp = outArr[a];
         outArr[a] = outArr[minIdx];
         outArr[minIdx] = tmp;
      }
   }
   return count;
}

//--- ボタン描画処理（最適化＆幅統一） ---
void UpdateMAButtonLook(string name, string label, bool state, color onColor)
{
   ObjectSetString(0, name, OBJPROP_TEXT, label + (state ? "(on)" : "(off)"));
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, state ? onColor : clrDarkGray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, state ? clrBlack : clrGainsboro);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}

void CreateSingleButtonAbs(string name, int width, int xPos, int yPos)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xPos);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, yPos);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 22);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
}

void CreateAllMAButtons()
{
   int btnW = 45;
   int gap  = 2;
   
   int yRow1 = MAButton_Y + 25; // 上段
   int yRow2 = MAButton_Y;      // 下段

   // 上段の配置 (右から順に: 下, 中, 上, 週, BB)
   int x = MAButton_X;
   CreateSingleButtonAbs(BTN_LOWER,  btnW, x, yRow1); x += btnW + gap;
   CreateSingleButtonAbs(BTN_MIDDLE, btnW, x, yRow1); x += btnW + gap;
   CreateSingleButtonAbs(BTN_UPPER,  btnW, x, yRow1); x += btnW + gap;
   CreateSingleButtonAbs(BTN_WEEKLY, btnW, x, yRow1); x += btnW + gap;
   CreateSingleButtonAbs(BTN_BB,     btnW, x, yRow1);

   // 下段の配置 (右から順に: Penta, DP, WP, Hide)
   x = MAButton_X;
   CreateSingleButtonAbs(BTN_PENTAGON, btnW + 5, x, yRow2); x += (btnW + 5) + gap;
   CreateSingleButtonAbs(BTN_DP,       btnW,     x, yRow2); x += btnW + gap;
   CreateSingleButtonAbs(BTN_WP,       btnW,     x, yRow2); x += btnW + gap;
   CreateSingleButtonAbs(BTN_HIDE,     btnW + 5, x, yRow2); 

   UpdateMAButtonLook(BTN_BB,     "BB", g_showBB,     clrCyan);
   UpdateMAButtonLook(BTN_WEEKLY, "週", g_showWeekly, clrYellow);
   UpdateMAButtonLook(BTN_UPPER,  "上", g_showUpper,  clrOrangeRed);
   UpdateMAButtonLook(BTN_MIDDLE, "中", g_showMiddle, clrLime);
   UpdateMAButtonLook(BTN_LOWER,  "下", g_showLower,  clrDeepSkyBlue);

   UpdateMAButtonLook(BTN_WP,     "WP", g_showWP,     clrGold);
   UpdateMAButtonLook(BTN_DP,     "DP", g_showDP,     clrOrange);

   UpdatePentagonButtonUI();

   ObjectSetString(0, BTN_HIDE, OBJPROP_TEXT, g_hideAllPanel ? "Show" : "Hide");
   ObjectSetInteger(0, BTN_HIDE, OBJPROP_BGCOLOR, g_hideAllPanel ? clrOrangeRed : clrGray);
   ObjectSetInteger(0, BTN_HIDE, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, BTN_HIDE, OBJPROP_BORDER_COLOR, clrWhite);
}

void UpdatePentagonButtonUI()
{
   string label = "Penta";
   if(g_showPentagon)
   {
      if(g_pentaClickStep == 0)      label = "P[1点]";
      else if(g_pentaClickStep == 1) label = "P[2点]";
      else                           label = "P[辺]";
   }
   UpdateMAButtonLook(BTN_PENTAGON, label, g_showPentagon, clrGold);
}

void CreateWeeklyFilterButton(int idx, int y)
{
   string name = BTN_W_FILTER_PREFIX + IntegerToString(idx);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, PanelCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 300); 
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 22);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 17);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrWhite);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 5);
   }

   bool state = g_useWeeklyFilterPerSymbol[idx];
   ObjectSetString(0, name, OBJPROP_TEXT, state ? "W" : "w");
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, state ? clrDodgerBlue : clrDimGray);
   ObjectSetInteger(0, name, OBJPROP_COLOR, state ? clrWhite : clrLightGray);

   if(g_hideAllPanel || g_showPentagon)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   else
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

//---------------- Pivot 描画機能 ----------------
void CreatePivotSegment(string name, datetime t1, datetime t2, double val, color clr, int width, ENUM_LINE_STYLE style, string label)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, val, t2, val);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, val);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, val);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString(0, name, OBJPROP_TEXT, label);
}

void DrawPivotLines()
{
   ObjectsDeleteAll(0, PIVOT_DP_PREFIX);
   ObjectsDeleteAll(0, PIVOT_WP_PREFIX);

   if(g_showDP && _Period < PERIOD_H4)
   {
      MqlRates rates[];
      int totalDays = PivotHistoryDays + 1;
      // 指定日数分(totalDays)きっちり揃っていない場合は描画しない。
      // 週末明けなどヒストリーデータの取得が完了していないタイミングで、
      // 少ない本数だけを使って「短い帯」を誤描画してしまうのを防ぐため。
      if(CopyRates(_Symbol, PERIOD_D1, 0, totalDays, rates) >= totalDays)
      {
         g_pivotDPReady = true;
         int count = ArraySize(rates);
         for(int i = 1; i < count; i++)
         {
            double H = rates[i-1].high;
            double L = rates[i-1].low;
            double C = rates[i-1].close;

            double P  = (H + L + C) / 3.0;
            double R1 = (2.0 * P) - L;
            double S1 = (2.0 * P) - H;
            double R2 = P + (H - L);
            double S2 = P - (H - L);

            datetime t1 = rates[i].time;
            datetime t2 = (i == count - 1) ? TimeCurrent() + PeriodSeconds(_Period) * 10 : rates[i].time + 86400;

            string pfx = PIVOT_DP_PREFIX + IntegerToString(i) + "_";
            CreatePivotSegment(pfx + "P",  t1, t2, P,  PivotPColor, 1, STYLE_SOLID, "DP Pivot");
            CreatePivotSegment(pfx + "R1", t1, t2, R1, PivotRColor, 1, STYLE_DASH,  "DP R1");
            CreatePivotSegment(pfx + "R2", t1, t2, R2, PivotRColor, 1, STYLE_DOT,   "DP R2");
            CreatePivotSegment(pfx + "S1", t1, t2, S1, PivotSColor, 1, STYLE_DASH,  "DP S1");
            CreatePivotSegment(pfx + "S2", t1, t2, S2, PivotSColor, 1, STYLE_DOT,   "DP S2");
         }
      }
   }

   if(g_showWP && _Period < PERIOD_D1)
   {
      MqlRates rates[];
      int totalWeeks = PivotHistoryWeeks + 1;
      // 同様に、指定週数分きっちり揃っていない場合は描画しない
      if(CopyRates(_Symbol, PERIOD_W1, 0, totalWeeks, rates) >= totalWeeks)
      {
         g_pivotWPReady = true;
         int count = ArraySize(rates);
         for(int i = 1; i < count; i++)
         {
            double H = rates[i-1].high;
            double L = rates[i-1].low;
            double C = rates[i-1].close;

            double P  = (H + L + C) / 3.0;
            double R1 = (2.0 * P) - L;
            double S1 = (2.0 * P) - H;
            double R2 = P + (H - L);
            double S2 = P - (H - L);

            datetime t1 = rates[i].time;
            datetime t2 = (i == count - 1) ? TimeCurrent() + PeriodSeconds(_Period) * 50 : rates[i].time + 7 * 86400;

            string pfx = PIVOT_WP_PREFIX + IntegerToString(i) + "_";
            CreatePivotSegment(pfx + "P",  t1, t2, P,  PivotPColor, 2, STYLE_SOLID, "WP Pivot");
            CreatePivotSegment(pfx + "R1", t1, t2, R1, PivotRColor, 1, STYLE_SOLID, "WP R1");
            CreatePivotSegment(pfx + "R2", t1, t2, R2, PivotRColor, 1, STYLE_DOT,   "WP R2");
            CreatePivotSegment(pfx + "S1", t1, t2, S1, PivotSColor, 1, STYLE_SOLID, "WP S1");
            CreatePivotSegment(pfx + "S2", t1, t2, S2, PivotSColor, 1, STYLE_DOT,   "WP S2");
         }
      }
   }
}

//---------------- ペンタゴン処理 ----------------
void RemoveGuideLine() { ObjectDelete(0, PENTAGON_GUIDE_LINE); }

void ClearPentagon()
{
   ObjectsDeleteAll(0, PENTAGON_OBJ_PREFIX);
   ObjectsDeleteAll(0, PENTAGON_EDGE_PREFIX);
   RemoveGuideLine();
   g_pentaClickStep = 0; 
   g_pentagonCounter = 0;
}

void DrawSingleLine(string name, datetime t1, double p1, datetime t2, double p2, bool isEdge)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else
   {
      ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, PentagonColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, isEdge ? PentagonWidth + 1 : PentagonWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE, isEdge ? STYLE_SOLID : STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, isEdge); 
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
}

void DrawPentagonGeometric(datetime t1, double p1, datetime t2, double p2, string pentaIdStr, bool isAdjacent = false, datetime centerRefT = 0, double centerRefP = 0)
{
   int x0, y0, x1p, y1p;
   bool conv0 = ChartTimePriceToXY(0, 0, t1, p1, x0, y0);
   bool conv1 = ChartTimePriceToXY(0, 0, t2, p2, x1p, y1p);

   if(!conv0 || !conv1)
   {
      datetime firstVisibleBar = (datetime)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
      int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
      double priceHigh = ChartGetDouble(0, CHART_PRICE_MAX);
      double priceLow  = ChartGetDouble(0, CHART_PRICE_MIN);
      int chartW       = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chartH       = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

      double secPerPixel = (visibleBars * PeriodSeconds(_Period)) / (double)MathMax(chartW, 1);
      double pricePerPixel = (priceHigh - priceLow) / (double)MathMax(chartH, 1);

      x0  = (secPerPixel > 0) ? (int)((t1 - firstVisibleBar) / secPerPixel) : 0;
      y0  = (pricePerPixel > 0) ? (int)((priceHigh - p1) / pricePerPixel) : 0;
      x1p = (secPerPixel > 0) ? (int)((t2 - firstVisibleBar) / secPerPixel) : 0;
      y1p = (pricePerPixel > 0) ? (int)((priceHigh - p2) / pricePerPixel) : 0;
   }

   double dx = x1p - x0;
   double dy = y1p - y0;
   double edgeLen = MathSqrt(dx * dx + dy * dy);
   if(edgeLen < 2.0) return;

   double midX = (x0 + x1p) / 2.0;
   double midY = (y0 + y1p) / 2.0;

   double nx = -dy / edgeLen;
   double ny =  dx / edgeLen;

   double apothem      = edgeLen / (2.0 * MathTan(M_PI / 5.0));
   double circumradius = edgeLen / (2.0 * MathSin(M_PI / 5.0));

   double centerX = midX + nx * apothem;
   double centerY = midY + ny * apothem;

   if(isAdjacent)
   {
      int refX, refY;
      if(ChartTimePriceToXY(0, 0, centerRefT, centerRefP, refX, refY))
      {
         double dist1 = MathPow(centerX - refX, 2) + MathPow(centerY - refY, 2);
         double altCenterX = midX - nx * apothem;
         double altCenterY = midY - ny * apothem;
         double dist2 = MathPow(altCenterX - refX, 2) + MathPow(altCenterY - refY, 2);
         if(dist1 < dist2)
         {
            centerX = altCenterX;
            centerY = altCenterY;
         }
      }
   }

   double angle0 = MathArctan2(y0 - centerY, x0 - centerX);
   double step = 2.0 * M_PI / 5.0;

   double fwdX1 = centerX + circumradius * MathCos(angle0 + step);
   double fwdY1 = centerY + circumradius * MathSin(angle0 + step);
   double bwdX1 = centerX + circumradius * MathCos(angle0 - step);
   double bwdY1 = centerY + circumradius * MathSin(angle0 - step);

   double distFwd = MathPow(fwdX1 - x1p, 2) + MathPow(fwdY1 - y1p, 2);
   double distBwd = MathPow(bwdX1 - x1p, 2) + MathPow(bwdY1 - y1p, 2);
   double dir = (distBwd < distFwd) ? -1.0 : 1.0;

   double vx[5], vy[5];
   for(int k = 0; k < 5; k++)
   {
      double ang = angle0 + dir * k * step;
      vx[k] = centerX + circumradius * MathCos(ang);
      vy[k] = centerY + circumradius * MathSin(ang);
   }

   datetime outT[5]; double outV[5];
   for(int k = 0; k < 5; k++)
   {
      datetime tempT; double tempV;
      if(ChartXYToTimePrice(0, (int)MathRound(vx[k]), (int)MathRound(vy[k]), x0, tempT, tempV))
      {
         outT[k] = tempT;
         outV[k] = tempV;
      }
      else
      {
         int visibleBars = (int)ChartGetInteger(0, CHART_VISIBLE_BARS);
         datetime firstBar = (datetime)ChartGetInteger(0, CHART_FIRST_VISIBLE_BAR);
         double priceHigh = ChartGetDouble(0, CHART_PRICE_MAX);
         double priceLow  = ChartGetDouble(0, CHART_PRICE_MIN);
         int chartW       = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int chartH       = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);

         double secPix = (visibleBars * PeriodSeconds(_Period)) / (double)MathMax(chartW, 1);
         double prcPix = (priceHigh - priceLow) / (double)MathMax(chartH, 1);

         outT[k] = firstBar + (datetime)MathRound(vx[k] * secPix);
         outV[k] = priceHigh - (vy[k] * prcPix);
      }
   }

   for(int k = 0; k < 5; k++)
   {
      int next = (k + 1) % 5;
      string edgeName = PENTAGON_EDGE_PREFIX + pentaIdStr + "_" + IntegerToString(k);
      DrawSingleLine(edgeName, outT[k], outV[k], outT[next], outV[next], true);
   }

   for(int k = 0; k < 5; k++)
   {
      int next = (k + 2) % 5;
      string diagName = PENTAGON_OBJ_PREFIX + "Diag_" + pentaIdStr + "_" + IntegerToString(k);
      DrawSingleLine(diagName, outT[k], outV[k], outT[next], outV[next], false);
   }
}

void CreateBasePentagon(datetime t1, double p1, datetime t2, double p2)
{
   g_pentagonCounter++;
   DrawPentagonGeometric(t1, p1, t2, p2, IntegerToString(g_pentagonCounter));
}

void AddAdjacentPentagon(string edgeObjName)
{
   datetime t1 = (datetime)ObjectGetInteger(0, edgeObjName, OBJPROP_TIME, 0);
   double   p1 = ObjectGetDouble(0, edgeObjName, OBJPROP_PRICE, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, edgeObjName, OBJPROP_TIME, 1);
   double   p2 = ObjectGetDouble(0, edgeObjName, OBJPROP_PRICE, 1);

   if(t1 == 0 || t2 == 0) return;

   g_pentagonCounter++;
   DrawPentagonGeometric(t1, p1, t2, p2, IntegerToString(g_pentagonCounter), true, (t1 + t2)/2, (p1 + p2)/2);
}

void SetRightUIElementsVisible(bool visible)
{
   for(int i = 0; i < g_symbolCount + 1; i++)
   {
      string name = (i == 0) ? "MTF_Panel_Title" : "MTF_Panel_Row_" + IntegerToString(i - 1);
      if(ObjectFind(0, name) >= 0)
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      
      if(i < g_symbolCount)
      {
         string wName = BTN_W_FILTER_PREFIX + IntegerToString(i);
         if(ObjectFind(0, wName) >= 0)
            ObjectSetInteger(0, wName, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      }
   }
}

//---------------- 値幅スクイーズ判定 ----------------
bool IsDailyRangeMin(string sym)
{
   MqlRates rates[];
   if(CopyRates(sym, PERIOD_D1, 1, 5, rates) < 5) return false;
   double currentRange = rates[4].high - rates[4].low;
   for(int i = 0; i < 4; i++)
   {
      if(rates[i].high - rates[i].low <= currentRange) return false;
   }
   return true;
}

bool IsWeeklyRangeMin(string sym)
{
   MqlRates rates[];
   if(CopyRates(sym, PERIOD_W1, 1, 4, rates) < 4) return false;
   double currentRange = rates[3].high - rates[3].low;
   for(int i = 0; i < 3; i++)
   {
      if(rates[i].high - rates[i].low <= currentRange) return false;
   }
   return true;
}

// 通貨ペアの実質的な1pipのサイズを返す（5桁/3桁ブローカーにも対応）
double GetPipSize(string sym)
{
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(digits == 3 || digits == 5) return point * 10.0;
   return point;
}

// 過去HighLowLookbackHours時間（H1足換算）の高値・安値に、現在価格が
// 指定pips以内まで近づいているかを判定する。戻り値: 1=高値付近, -1=安値付近, 0=該当なし
int CheckNearHighLow(string sym)
{
   if(!UseHighLowAlert) return 0;
   if(HighLowLookbackHours <= 0) return 0;

   MqlRates rates[];
   int copied = CopyRates(sym, PERIOD_H1, 0, HighLowLookbackHours, rates);
   // 指定した本数(HighLowLookbackHours)がきっちり揃っていない場合は計算しない。
   // 週末明けなどでヒストリーデータの取得が完了していないタイミングで、
   // 少ない本数だけを使って「狭い高値・安値」を誤計算してしまうのを防ぐため。
   if(copied < HighLowLookbackHours) return 0;

   double hh = rates[0].high, ll = rates[0].low;
   for(int i = 1; i < copied; i++)
   {
      if(rates[i].high > hh) hh = rates[i].high;
      if(rates[i].low  < ll) ll = rates[i].low;
   }

   double price = SymbolInfoDouble(sym, SYMBOL_BID);
   if(price <= 0) return 0;

   double threshold = HighLowProximityPips * GetPipSize(sym);
   if(threshold <= 0) return 0;

   if(MathAbs(price - hh) <= threshold) return 1;
   if(MathAbs(price - ll) <= threshold) return -1;
   return 0;
}

// 通貨2つ(cur1,cur2)から、FX会社が実際に提供している銘柄名を探す。
// cur1+cur2 が無ければ cur2+cur1 を試し、見つかった方を返す（無ければ空文字）。
// reversed=true の場合、実際の銘柄は基準通貨と決済通貨が入れ替わっている。
string ResolveBrokerPair(string cur1, string cur2, bool &reversed)
{
   reversed = false;
   string symA = cur1 + cur2;
   if((bool)SymbolInfoInteger(symA, SYMBOL_EXIST)) return symA;

   string symB = cur2 + cur1;
   if((bool)SymbolInfoInteger(symB, SYMBOL_EXIST))
   {
      reversed = true;
      return symB;
   }
   return "";
}

//+------------------------------------------------------------------+
//| 初期化                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   SetIndexBuffer(0, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, WeeklyFastBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, WeeklySlowBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, UpperFastBuffer,  INDICATOR_DATA);
   SetIndexBuffer(5, UpperSlowBuffer,  INDICATOR_DATA);
   SetIndexBuffer(6, MiddleFastBuffer, INDICATOR_DATA);
   SetIndexBuffer(7, MiddleSlowBuffer, INDICATOR_DATA);
   SetIndexBuffer(8, LowerFastBuffer,  INDICATOR_DATA);
   SetIndexBuffer(9, LowerSlowBuffer,  INDICATOR_DATA);
   SetIndexBuffer(10, BBUpperBuffer,    INDICATOR_DATA);
   SetIndexBuffer(11, BBMiddleBuffer,   INDICATOR_DATA);
   SetIndexBuffer(12, BBLowerBuffer,    INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   for(int p = 0; p < 13; p++)
      PlotIndexSetDouble(p, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   g_symbolCount = ParseSymbols(InpSymbols, g_symbols);
   if(g_symbolCount <= 0) return(INIT_FAILED);

   ArrayResize(g_hWeeklyFast, g_symbolCount);
   ArrayResize(g_hWeeklySlow, g_symbolCount);
   ArrayResize(g_hUpperFast,  g_symbolCount);
   ArrayResize(g_hUpperSlow,  g_symbolCount);
   ArrayResize(g_hMiddleFast, g_symbolCount);
   ArrayResize(g_hMiddleSlow, g_symbolCount);
   ArrayResize(g_hLowerFast,  g_symbolCount);
   ArrayResize(g_hLowerSlow,  g_symbolCount);

   ArrayResize(g_hBB_Daily,   g_symbolCount);
   ArrayResize(g_hBB_Weekly,  g_symbolCount);
   ArrayResize(g_hBB_H4,      g_symbolCount);

   ArrayResize(g_signalCount, g_symbolCount);
   ArrayResize(g_signalCountNoWeekly, g_symbolCount);

   ArrayResize(g_lastSignalBarTime, g_symbolCount);
   ArrayInitialize(g_lastSignalBarTime, 0);

   ArrayResize(g_lastSignalBarTimeNoWeekly, g_symbolCount);
   ArrayInitialize(g_lastSignalBarTimeNoWeekly, 0);

   ArrayResize(g_useWeeklyFilterPerSymbol, g_symbolCount);
   for(int i = 0; i < g_symbolCount; i++) g_useWeeklyFilterPerSymbol[i] = true; 

   ArrayResize(g_lastHLAlertTime, g_symbolCount);
   ArrayInitialize(g_lastHLAlertTime, 0);

   ArrayResize(lastAlertBarTime, g_symbolCount);
   ArrayInitialize(lastAlertBarTime, 0);

   ArrayResize(g_lastDPSqueezeAlertTime, g_symbolCount);
   ArrayInitialize(g_lastDPSqueezeAlertTime, 0);

   ArrayResize(g_lastWPSqueezeAlertTime, g_symbolCount);
   ArrayInitialize(g_lastWPSqueezeAlertTime, 0);

   g_currentSymbolIndex = -1;

   for(int i = 0; i < g_symbolCount; i++)
   {
      string sym = g_symbols[i];
      string gvarName = CountVarName(sym);

      if(ResetCountsOnLoad) { GlobalVariableSet(gvarName, 0); g_signalCount[i] = 0; }
      else if(GlobalVariableCheck(gvarName)) { g_signalCount[i] = (int)GlobalVariableGet(gvarName); }
      else { GlobalVariableSet(gvarName, 0); g_signalCount[i] = 0; }

      string gvarNameNoW = CountNoWeeklyVarName(sym);
      if(ResetCountsOnLoad) { GlobalVariableSet(gvarNameNoW, 0); g_signalCountNoWeekly[i] = 0; }
      else if(GlobalVariableCheck(gvarNameNoW)) { g_signalCountNoWeekly[i] = (int)GlobalVariableGet(gvarNameNoW); }
      else { GlobalVariableSet(gvarNameNoW, 0); g_signalCountNoWeekly[i] = 0; }

      string gvarNameWF = WeeklyFilterVarName(sym);
      if(GlobalVariableCheck(gvarNameWF))
         g_useWeeklyFilterPerSymbol[i] = (GlobalVariableGet(gvarNameWF) != 0);
      else
      {
         GlobalVariableSet(gvarNameWF, 1); 
         g_useWeeklyFilterPerSymbol[i] = true;
      }

      SymbolSelect(sym, true);

      g_hWeeklyFast[i] = iMA(sym, TF_Weekly, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hWeeklySlow[i] = iMA(sym, TF_Weekly, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hUpperFast[i]  = iMA(sym, TF_Upper,  EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hUpperSlow[i]  = iMA(sym, TF_Upper,  EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hMiddleFast[i] = iMA(sym, TF_Middle, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hMiddleSlow[i] = iMA(sym, TF_Middle, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hLowerFast[i]  = iMA(sym, TF_Lower,  EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
      g_hLowerSlow[i]  = iMA(sym, TF_Lower,  EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);

      g_hBB_Daily[i]  = iBands(sym, TF_Upper,  Bands_Period, 0, BB_Filter_Dev, PRICE_CLOSE);
      g_hBB_Weekly[i] = iBands(sym, TF_Weekly, Bands_Period, 0, BB_Filter_Dev, PRICE_CLOSE);
      g_hBB_H4[i]     = iBands(sym, PERIOD_H4, Bands_Period, 0, BB_Filter_Dev, PRICE_CLOSE);

      if(sym == _Symbol) g_currentSymbolIndex = i;
   }

   g_hBB = iBands(_Symbol, _Period, Bands_Period, 0, Bands_Dev, PRICE_CLOSE);

   g_lastResetBoundary = GetCurrentResetBoundary();
   g_maLinesFilled = false;

   g_showWeekly = Show_Weekly_Default;
   g_showUpper  = Show_Upper_Default;
   g_showMiddle = Show_Middle_Default;
   g_showLower  = Show_Lower_Default;
   g_showBB     = Show_BB_Default;
   g_showDP     = Show_DP_Default;
   g_showWP     = Show_WP_Default;

   if(UseMAButtons) CreateAllMAButtons();
   DrawPivotLines();

   if(UseCurrencyStrength)
      ComputeCurrencyStrength();

   ChartRedraw(0);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
   ObjectsDeleteAll(0, "MTF_Panel_");
   ObjectsDeleteAll(0, "MTF_Rank_");
   ObjectsDeleteAll(0, BTN_W_FILTER_PREFIX);
   ObjectsDeleteAll(0, PIVOT_DP_PREFIX);
   ObjectsDeleteAll(0, PIVOT_WP_PREFIX);
   ClearPentagon();

   ObjectDelete(0, BTN_WEEKLY);
   ObjectDelete(0, BTN_UPPER);
   ObjectDelete(0, BTN_MIDDLE);
   ObjectDelete(0, BTN_LOWER);
   ObjectDelete(0, BTN_BB);
   ObjectDelete(0, BTN_DP);
   ObjectDelete(0, BTN_WP);
   ObjectDelete(0, BTN_PENTAGON);
   ObjectDelete(0, BTN_HIDE);

   if(g_hBB != INVALID_HANDLE) IndicatorRelease(g_hBB);
}

int GetTrend(int hFast, int hSlow)
{
   double fastArr[], slowArr[];
   ArraySetAsSeries(fastArr, true); ArraySetAsSeries(slowArr, true);
   int need = Slope_Lookback + 2;
   if(CopyBuffer(hFast, 0, 0, need, fastArr) < need) return 0;
   if(CopyBuffer(hSlow, 0, 0, need, slowArr) < need) return 0;

   bool fastAboveSlow = fastArr[0] > slowArr[0];
   bool fastBelowSlow = fastArr[0] < slowArr[0];
   double slope = fastArr[0] - fastArr[Slope_Lookback];

   if(fastAboveSlow && slope > 0) return 1;
   if(fastBelowSlow && slope < 0) return -1;
   return 0;
}

int CheckBBExceed(string sym, ENUM_TIMEFRAMES tf, int hBB)
{
   if(hBB == INVALID_HANDLE) return 0;
   double uBuf[1], lBuf[1], cBuf[1];
   if(CopyBuffer(hBB, UPPER_BAND, 0, 1, uBuf) < 1) return 0;
   if(CopyBuffer(hBB, LOWER_BAND, 0, 1, lBuf) < 1) return 0;
   if(CopyClose(sym, tf, 0, 1, cBuf) < 1) return 0;

   if(cBuf[0] > uBuf[0]) return 1;
   if(cBuf[0] < lBuf[0]) return -1;
   return 0;
}

string TrendArrow(int trend)
{
   if(trend == 1)  return "↑";
   if(trend == -1) return "↓";
   return "-";
}

string TrendText(int trend)
{
   if(trend == 1)  return "上昇 ↑";
   if(trend == -1) return "下降 ↓";
   return "レンジ -";
}

int GetPanelY(int row)
{
   return 20 + row * 20;
}

//+------------------------------------------------------------------+
//| 通貨強弱インジケーター                                             |
//+------------------------------------------------------------------+
int MajorIndex(string cur)
{
   for(int i = 0; i < MAJOR_COUNT; i++)
      if(g_majors[i] == cur) return i;
   return -1;
}

// rank(1=最強～7=最弱)を、赤(最強)→青(最弱)のグラデーションに変換する
color RankColor(int rank)
{
   double t = (double)(rank - 1) / (double)(MAJOR_COUNT - 1); // 0=最強 .. 1=最弱
   int r = (int)MathRound(255.0 * (1.0 - t));
   int b = (int)MathRound(255.0 * t);
   int g = 0;
   return (color)(r + (g << 8) + (b << 16));
}

// 主要7通貨の強弱を計算する。各通貨ペアの直近確定足(StrengthTF)が陽線なら分子通貨に+1、
// 陰線なら分母通貨に+1。対象は「両方の通貨が主要7通貨に含まれる」ペアのみ。
void ComputeCurrencyStrength()
{
   double score[MAJOR_COUNT];
   ArrayInitialize(score, 0.0);

   for(int i = 0; i < g_symbolCount; i++)
   {
      string sym = g_symbols[i];
      if(StringLen(sym) != 6) continue;

      string cur1 = StringSubstr(sym, 0, 3);
      string cur2 = StringSubstr(sym, 3, 3);
      int idx1 = MajorIndex(cur1);
      int idx2 = MajorIndex(cur2);
      if(idx1 < 0 || idx2 < 0) continue; // 主要7通貨のペアだけを対象にする

      double o1 = iOpen(sym, StrengthTF, 1);  // 直近確定足（形成中の足はノイズが大きいので使わない）
      double c1 = iClose(sym, StrengthTF, 1);
      if(o1 <= 0 || c1 <= 0) continue;

      if(c1 > o1)      score[idx1] += 1.0; // 上昇 → 分子(先頭)通貨に加点
      else if(c1 < o1) score[idx2] += 1.0; // 下降 → 分母(末尾)通貨に加点
   }

   ArrayCopy(g_currencyScore, score);

   int order[MAJOR_COUNT];
   for(int i = 0; i < MAJOR_COUNT; i++) order[i] = i;
   for(int a = 0; a < MAJOR_COUNT - 1; a++)
      for(int b = a + 1; b < MAJOR_COUNT; b++)
         if(g_currencyScore[order[b]] > g_currencyScore[order[a]])
         { int tmp = order[a]; order[a] = order[b]; order[b] = tmp; }

   for(int r = 0; r < MAJOR_COUNT; r++)
      g_currencyRank[order[r]] = r + 1;

   for(int i = 0; i < MAJOR_COUNT; i++)
      g_currencyColor[i] = RankColor(g_currencyRank[i]);
}

// 通貨コード(3文字)に対応する色を返す。主要7通貨でなければ既定色(白)を返す
color CurrencyColorOf(string cur, color defaultColor)
{
   int idx = MajorIndex(cur);
   if(idx < 0) return defaultColor;
   return g_currencyColor[idx];
}

// 実際のフォント(Consolas, 9pt)でテキストを描画した時のピクセル幅を正確に測定する。
// 「1文字あたりの推定幅」による位置ズレを避けるため、TextGetSize()で実測する。
int MeasureTextWidth(string text)
{
   TextSetFont("Consolas", -9, 0, 0);
   uint w = 0, h = 0;
   TextGetSize(text, w, h);
   return (int)w;
}

// 部分文字列だけを色付けするための小さいラベルを描画する（左詰めアンカーで、
// 右コーナー基準のXDISTANCEを使うことで、右詰めの行の途中にぴったり重ねられる）
void DrawSubLabel(string name, int y, int xDistance, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, PanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, xDistance);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);

   if(g_hideAllPanel || g_showPentagon)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   else
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

// 通貨ペア名の部分だけ、各通貨の強弱に応じて色分けする。
// 主要7通貨のペア以外（GOLD, BTCUSDなど）は通常通り単一色のまま。
void DrawSymbolWithCurrencyColors(int rowIdx, int y, string sym, string restText, color restColor)
{
   // 通貨コードの色分けは廃止（白色に統一）したため、以前のように行を複数の
   // ラベルに分割して個別に色を付ける必要はない。TextGetSizeによる幅測定が
   // 環境によってはうまく機能せず行が表示されなくなる不具合があったため、
   // シンプルな単一ラベル表示に戻す。
   string fullText = StringFormat("%-7s", sym) + restText;

   string sym1Name = "MTF_Panel_Cur1_" + IntegerToString(rowIdx);
   string sym2Name = "MTF_Panel_Cur2_" + IntegerToString(rowIdx);
   string restName = "MTF_Panel_Row_"  + IntegerToString(rowIdx);

   // 過去のバージョンで作られた分割ラベルが残っていれば削除しておく
   ObjectDelete(0, sym1Name);
   ObjectDelete(0, sym2Name);

   DrawPanelLabel(restName, y, fullText, restColor);
}

// 右下の空きスペースに、主要通貨の強弱ランキングを横並び1行で表示する
void DrawCurrencyRankingPanel()
{
   if(!UseCurrencyStrength || !ShowCurrencyRanking)
   {
      ObjectsDeleteAll(0, "MTF_Rank_");
      return;
   }

   int order[MAJOR_COUNT];
   for(int i = 0; i < MAJOR_COUNT; i++) order[i] = i;
   for(int a = 0; a < MAJOR_COUNT - 1; a++)
      for(int b = a + 1; b < MAJOR_COUNT; b++)
         if(g_currencyScore[order[b]] > g_currencyScore[order[a]])
         { int tmp = order[a]; order[a] = order[b]; order[b] = tmp; }

   int slotWidth = 46; // 1通貨あたりの横幅(px)

   // タイトル（一番右、行の右端）
   string titleName = "MTF_Rank_Title";
   if(ObjectFind(0, titleName) < 0)
   {
      ObjectCreate(0, titleName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, titleName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, titleName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, titleName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, titleName, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, titleName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, titleName, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, titleName, OBJPROP_XDISTANCE, RankingPanel_X);
   ObjectSetInteger(0, titleName, OBJPROP_YDISTANCE, RankingPanel_Y + 16);
   ObjectSetString(0, titleName, OBJPROP_TEXT, StringFormat("通貨強弱(%s)", EnumToString(StrengthTF)));
   ObjectSetInteger(0, titleName, OBJPROP_COLOR, clrWhite);

   // 1位を一番左、7位を一番右（＝右端に近い側）にして横並びに配置する
   for(int r = 0; r < MAJOR_COUNT; r++)
   {
      int curIdx = order[r];
      string name = "MTF_Rank_Row_" + IntegerToString(r);
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_BACK, false);
      }
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, RankingPanel_X + (MAJOR_COUNT - 1 - r) * slotWidth);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, RankingPanel_Y);

      string line = StringFormat("%d%s", r + 1, g_majors[curIdx]);
      ObjectSetString(0, name, OBJPROP_TEXT, line);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   }

   // 最強通貨と最弱通貨を組み合わせた通貨ペアを表示する。
   // FX会社に実際に存在する銘柄名（例：USDCHFはあるがCHFUSDは無い、など）を優先して使い、
   // 直近確定足の陽線/陰線から「上昇」「下降」も判定して表示する。
   string bestPairName = "MTF_Rank_BestPair";
   if(ObjectFind(0, bestPairName) < 0)
   {
      ObjectCreate(0, bestPairName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bestPairName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, bestPairName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, bestPairName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, bestPairName, OBJPROP_BACK, false);
   }
   ObjectSetInteger(0, bestPairName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, bestPairName, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, bestPairName, OBJPROP_XDISTANCE, RankingPanel_X);
   ObjectSetInteger(0, bestPairName, OBJPROP_YDISTANCE, RankingPanel_Y + 32);

   string strongest = g_majors[order[0]];
   string weakest   = g_majors[order[MAJOR_COUNT - 1]];

   bool reversed = false;
   string brokerSym = ResolveBrokerPair(strongest, weakest, reversed);

   string bestPairText;
   color  bestPairColor = clrWhite;

   if(brokerSym != "")
   {
      g_bestPairSymbol = brokerSym;
      SymbolSelect(brokerSym, true);

      double o1 = iOpen(brokerSym, StrengthTF, 1);
      double c1 = iClose(brokerSym, StrengthTF, 1);

      string dirText = "-";
      if(o1 > 0 && c1 > 0)
      {
         if(c1 > o1)      dirText = "上昇↑";
         else if(c1 < o1) dirText = "下降↓";
      }

      bestPairText = StringFormat("最強/最弱: %s %s (クリックで表示)", brokerSym, dirText);
   }
   else
   {
      // 稀にどちらの組み合わせも提供されていない場合
      g_bestPairSymbol = "";
      bestPairText = StringFormat("最強/最弱: %s%s (銘柄未提供)", strongest, weakest);
   }

   ObjectSetString(0, bestPairName, OBJPROP_TEXT, bestPairText);
   ObjectSetInteger(0, bestPairName, OBJPROP_COLOR, bestPairColor);
}

void DrawPanelLabel(string name, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 1);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, PanelCorner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 15);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);

   if(g_hideAllPanel || g_showPentagon)
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   else
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}

bool IsHigherTFReady(string sym, ENUM_TIMEFRAMES tf, int hFast, int hSlow)
{
   int availableBars = Bars(sym, tf);
   if(availableBars <= 0) return false;
   int need = MathMin(availableBars, MaxHighTFBars);
   if(need <= 0) return false;
   double tmp[];
   if(CopyBuffer(hFast, 0, 0, need, tmp) < need) return false;
   if(CopyBuffer(hSlow, 0, 0, need, tmp) < need) return false;
   return true;
}

void FillHigherTFLine(string sym, ENUM_TIMEFRAMES tf, int hFast, int hSlow,
                      const datetime &lowTime[], int lowStart, int lowTotal,
                      double &fastBuf[], double &slowBuf[])
{
   int availableBars = Bars(sym, tf);
   if(availableBars <= 0) return;
   int highBars = MathMin(availableBars, MaxHighTFBars);

   double fastArr[], slowArr[]; datetime timeArr[];
   ArraySetAsSeries(fastArr, false); ArraySetAsSeries(slowArr, false); ArraySetAsSeries(timeArr, false);

   int cf = CopyBuffer(hFast, 0, 0, highBars, fastArr);
   int cs = CopyBuffer(hSlow, 0, 0, highBars, slowArr);
   int ct = CopyTime(sym, tf, 0, highBars, timeArr);
   int n = MathMin(cf, MathMin(cs, ct));
   if(n <= 0) return;

   int j = 0;
   for(int i = lowStart; i < lowTotal; i++)
   {
      datetime t = lowTime[i];
      while(j + 1 < n && timeArr[j + 1] <= t) j++;
      if(timeArr[j] <= t)
      {
         fastBuf[i] = fastArr[j];
         slowBuf[i] = slowArr[j];
      }
   }
}

//+------------------------------------------------------------------+
//| メイン計算                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // 毎Tick計算の超高速化処理
   int start = (prev_calculated > 1) ? prev_calculated - 1 : 0;

   // --- Pivotラインのデータがまだ揃っていなければ再試行する ---
   // （週末明け等でヒストリーデータの取得が完了していないタイミングで
   //   OnInit時の初回描画が失敗した場合、データが揃い次第自動で描画し直す）
   if((g_showDP && !g_pivotDPReady) || (g_showWP && !g_pivotWPReady))
      DrawPivotLines();

   if(UseCurrencyStrength)
      ComputeCurrencyStrength();

   if(UseDailyReset)
   {
      datetime currentBoundary = GetCurrentResetBoundary();
      if(currentBoundary != g_lastResetBoundary)
      {
         ResetAllSignalCounts();
         g_lastResetBoundary = currentBoundary;
      }
   }

   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, g_showWeekly ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, g_showWeekly ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, g_showUpper  ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, g_showUpper  ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(6, PLOT_DRAW_TYPE, g_showMiddle ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(7, PLOT_DRAW_TYPE, g_showMiddle ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(8, PLOT_DRAW_TYPE, g_showLower  ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(9, PLOT_DRAW_TYPE, g_showLower  ? DRAW_LINE : DRAW_NONE);

   PlotIndexSetInteger(10, PLOT_DRAW_TYPE, g_showBB ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(11, PLOT_DRAW_TYPE, g_showBB ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(12, PLOT_DRAW_TYPE, g_showBB ? DRAW_LINE : DRAW_NONE);

   for(int i = start; i < rates_total; i++)
   {
      BuySignalBuffer[i]  = EMPTY_VALUE; SellSignalBuffer[i] = EMPTY_VALUE;
      WeeklyFastBuffer[i] = EMPTY_VALUE; WeeklySlowBuffer[i] = EMPTY_VALUE;
      UpperFastBuffer[i]  = EMPTY_VALUE; UpperSlowBuffer[i]  = EMPTY_VALUE;
      MiddleFastBuffer[i] = EMPTY_VALUE; MiddleSlowBuffer[i] = EMPTY_VALUE;
      LowerFastBuffer[i]  = EMPTY_VALUE; LowerSlowBuffer[i]  = EMPTY_VALUE;
      BBUpperBuffer[i]    = EMPTY_VALUE; BBMiddleBuffer[i]   = EMPTY_VALUE; BBLowerBuffer[i] = EMPTY_VALUE;
   }

   // BB描画の高速コピー処理
   if(g_showBB && g_hBB != INVALID_HANDLE)
   {
      int toCopy = rates_total - start;
      if(toCopy > 0)
      {
         double tempUpper[], tempMiddle[], tempLower[];
         ArraySetAsSeries(tempUpper, false); ArraySetAsSeries(tempMiddle, false); ArraySetAsSeries(tempLower, false);
         if(CopyBuffer(g_hBB, UPPER_BAND, start, toCopy, tempUpper) == toCopy &&
            CopyBuffer(g_hBB, BASE_LINE,  start, toCopy, tempMiddle) == toCopy &&
            CopyBuffer(g_hBB, LOWER_BAND, start, toCopy, tempLower) == toCopy)
         {
            for(int k = 0; k < toCopy; k++)
            {
               BBUpperBuffer[start + k]  = tempUpper[k];
               BBMiddleBuffer[start + k] = tempMiddle[k];
               BBLowerBuffer[start + k]  = tempLower[k];
            }
         }
      }
   }

   if(g_currentSymbolIndex >= 0)
   {
      int ci = g_currentSymbolIndex;
      string curSym = g_symbols[ci];

      if(!g_maLinesFilled)
      {
         bool allReady =
            (!g_showWeekly || IsHigherTFReady(curSym, TF_Weekly, g_hWeeklyFast[ci], g_hWeeklySlow[ci])) &&
            (!g_showUpper  || IsHigherTFReady(curSym, TF_Upper,  g_hUpperFast[ci],  g_hUpperSlow[ci]))  &&
            (!g_showMiddle || IsHigherTFReady(curSym, TF_Middle, g_hMiddleFast[ci], g_hMiddleSlow[ci])) &&
            (!g_showLower  || IsHigherTFReady(curSym, TF_Lower,  g_hLowerFast[ci],  g_hLowerSlow[ci]));

         if(allReady)
         {
            if(g_showWeekly) FillHigherTFLine(curSym, TF_Weekly, g_hWeeklyFast[ci], g_hWeeklySlow[ci], time, 0, rates_total, WeeklyFastBuffer, WeeklySlowBuffer);
            if(g_showUpper)  FillHigherTFLine(curSym, TF_Upper,  g_hUpperFast[ci],  g_hUpperSlow[ci],  time, 0, rates_total, UpperFastBuffer, UpperSlowBuffer);
            if(g_showMiddle) FillHigherTFLine(curSym, TF_Middle, g_hMiddleFast[ci], g_hMiddleSlow[ci], time, 0, rates_total, MiddleFastBuffer, MiddleSlowBuffer);
            if(g_showLower)  FillHigherTFLine(curSym, TF_Lower,  g_hLowerFast[ci],  g_hLowerSlow[ci],  time, 0, rates_total, LowerFastBuffer, LowerSlowBuffer);
            g_maLinesFilled = true;
         }
      }
      else
      {
         if(g_showWeekly) FillHigherTFLine(curSym, TF_Weekly, g_hWeeklyFast[ci], g_hWeeklySlow[ci], time, start, rates_total, WeeklyFastBuffer, WeeklySlowBuffer);
         if(g_showUpper)  FillHigherTFLine(curSym, TF_Upper,  g_hUpperFast[ci],  g_hUpperSlow[ci],  time, start, rates_total, UpperFastBuffer, UpperSlowBuffer);
         if(g_showMiddle) FillHigherTFLine(curSym, TF_Middle, g_hMiddleFast[ci], g_hMiddleSlow[ci], time, start, rates_total, MiddleFastBuffer, MiddleSlowBuffer);
         if(g_showLower)  FillHigherTFLine(curSym, TF_Lower,  g_hLowerFast[ci],  g_hLowerSlow[ci],  time, start, rates_total, LowerFastBuffer, LowerSlowBuffer);
      }
   }

   if(UsePanel)
   {
      int totalSignals = 0;
      int totalSignalsNoW = 0;
      for(int s = 0; s < g_symbolCount; s++)
      {
         totalSignals += g_signalCount[s];
         totalSignalsNoW += g_signalCountNoWeekly[s];
      }
      string maStatus = (g_currentSymbolIndex < 0) ? "MA:対象外" : (g_maLinesFilled ? "MA:表示中" : "MA:準備中");

      DrawPanelLabel("MTF_Panel_Title", GetPanelY(0),
         StringFormat("MTF[週/上/中/下] 合計:%d/%d %s", totalSignals, totalSignalsNoW, maStatus), clrWhite);
   }

   for(int i = 0; i < g_symbolCount; i++)
   {
      string sym = g_symbols[i];
      int tWeekly = GetTrend(g_hWeeklyFast[i], g_hWeeklySlow[i]);
      int tUp     = GetTrend(g_hUpperFast[i],  g_hUpperSlow[i]);
      int tMid    = GetTrend(g_hMiddleFast[i], g_hMiddleSlow[i]);
      int tLow    = GetTrend(g_hLowerFast[i],  g_hLowerSlow[i]);

      int bbDailyExceed  = CheckBBExceed(sym, TF_Upper,  g_hBB_Daily[i]);
      int bbWeeklyExceed = CheckBBExceed(sym, TF_Weekly, g_hBB_Weekly[i]);
      int bbH4Exceed     = CheckBBExceed(sym, PERIOD_H4, g_hBB_H4[i]);

      string bbFlag = "";
      if(bbDailyExceed != 0)  bbFlag += "d";
      if(bbWeeklyExceed != 0) bbFlag += "w";
      if(bbH4Exceed != 0)     bbFlag += "4";
      if(bbFlag == "")        bbFlag = " ";

      bool dSq = IsDailyRangeMin(sym);
      bool wSq = IsWeeklyRangeMin(sym);
      string sqFlag = "";
      if(dSq && wSq)      sqFlag = "WD-SQ ";
      else if(wSq)        sqFlag = "W-SQ ";
      else if(dSq)        sqFlag = "D-SQ ";

      if(dSq && TimeCurrent() - g_lastDPSqueezeAlertTime[i] > 86400)
      {
         g_lastDPSqueezeAlertTime[i] = TimeCurrent();
         string sqMsg = sym + ": 日足値幅が過去1週間で最も狭くなっています（ブレイク注意）";
         if(UseAlert && AlertOnSqueeze) Alert(sqMsg);
         if(UsePush  && AlertOnSqueeze) SendNotification(sqMsg);
      }
      if(wSq && TimeCurrent() - g_lastWPSqueezeAlertTime[i] > 86400 * 7)
      {
         g_lastWPSqueezeAlertTime[i] = TimeCurrent();
         string sqMsg = sym + ": 週足値幅が過去1か月で最も狭くなっています（ブレイク注意）";
         if(UseAlert && AlertOnSqueeze) Alert(sqMsg);
         if(UsePush  && AlertOnSqueeze) SendNotification(sqMsg);
      }

      int nearHL = CheckNearHighLow(sym); // 1=高値付近, -1=安値付近, 0=なし
      string hlFlag = "";
      if(nearHL == 1)       hlFlag = "H!";
      else if(nearHL == -1) hlFlag = "L!";

      if(nearHL != 0)
      {
         datetime nowT = TimeCurrent();
         if(nowT - g_lastHLAlertTime[i] > HighLowAlertCooldownMin * 60)
         {
            g_lastHLAlertTime[i] = nowT;
            string hlMsg = sym + (nearHL == 1
               ? StringFormat(": 過去%d時間の高値付近まで接近しています", HighLowLookbackHours)
               : StringFormat(": 過去%d時間の安値付近まで接近しています", HighLowLookbackHours));
            if(UseAlert && AlertOnHighLow) Alert(hlMsg);
            if(UsePush  && AlertOnHighLow) SendNotification(hlMsg);
         }
      }

      bool baseBuy  = (tUp == 1  && tLow == 1  && tMid == -1);
      bool baseSell = (tUp == -1 && tLow == -1 && tMid == 1);

      bool useWFilter = g_useWeeklyFilterPerSymbol[i];
      bool buySignal  = baseBuy  && (!useWFilter || tWeekly == 1);
      bool sellSignal = baseSell && (!useWFilter || tWeekly == -1);

      string tag = buySignal ? "B" : (sellSignal ? "S" : "-");

      color rowColor = clrWhite;
      if(bbDailyExceed != 0 || bbWeeklyExceed != 0 || bbH4Exceed != 0)
         rowColor = PanelExceedColor;
      else if(nearHL != 0)
         rowColor = clrOrange;
      else if(buySignal)
         rowColor = PanelUpColor;
      else if(sellSignal)
         rowColor = PanelDownColor;

      if(buySignal || sellSignal)
      {
         datetime symBarTime = iTime(sym, TF_Lower, 0);
         if(symBarTime != g_lastSignalBarTime[i] && symBarTime != 0)
         {
            g_lastSignalBarTime[i] = symBarTime;
            g_signalCount[i]++;
            GlobalVariableSet(CountVarName(sym), g_signalCount[i]);
         }
      }

      if(baseBuy || baseSell)
      {
         datetime symBarTimeNoW = iTime(sym, TF_Lower, 0);
         if(symBarTimeNoW != g_lastSignalBarTimeNoWeekly[i] && symBarTimeNoW != 0)
         {
            g_lastSignalBarTimeNoWeekly[i] = symBarTimeNoW;
            g_signalCountNoWeekly[i]++;
            GlobalVariableSet(CountNoWeeklyVarName(sym), g_signalCountNoWeekly[i]);
         }
      }

      if(UsePanel)
      {
         int yPos = GetPanelY(i + 1);
         CreateWeeklyFilterButton(i, yPos);

         string restText = StringFormat("[%3s]%s%s %s%s%s%s %s(%d/%d)",
            bbFlag, sqFlag, hlFlag, TrendArrow(tWeekly), TrendArrow(tUp), TrendArrow(tMid), TrendArrow(tLow),
            tag, g_signalCount[i], g_signalCountNoWeekly[i]);

         DrawSymbolWithCurrencyColors(i, yPos, sym, restText, rowColor);
      }

      // --- 矢印の描画は「今見ているチャートの通貨ペア」のみ ---
      if(i == g_currentSymbolIndex)
      {
         int lastIndex = rates_total - 1;
         if(lastIndex >= 0)
         {
            if(buySignal)  BuySignalBuffer[lastIndex]  = low[lastIndex] - 10 * _Point;
            if(sellSignal) SellSignalBuffer[lastIndex] = high[lastIndex] + 10 * _Point;
         }
      }

      // --- 週波/大波/中波/小波の売買シグナルアラートは「全通貨ペア」で独立して鳴らす ---
      if(buySignal || sellSignal)
      {
         datetime symBarTimeAlert = iTime(sym, TF_Lower, 0);
         if(symBarTimeAlert != lastAlertBarTime[i] && symBarTimeAlert != 0)
         {
            lastAlertBarTime[i] = symBarTimeAlert;
            string dir = buySignal ? "買い(BUY)" : "売り(SELL)";
            string msg = sym + " : " + dir + " シグナル発生\n"
                         + "週足=" + (useWFilter ? TrendText(tWeekly) : "無視")
                         + " / 上足=" + TrendText(tUp)
                         + " / 中足=" + TrendText(tMid)
                         + " / 下足=" + TrendText(tLow);

            if(UseAlert && AlertOnTrendSignal) Alert(msg);
            if(UsePush  && AlertOnTrendSignal) SendNotification(msg);
         }
      }
   }

   if(UsePanel)
      DrawCurrencyRankingPanel();

   return(rates_total);
}

//+------------------------------------------------------------------+
//| チャートイベント                                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(g_showPentagon && g_pentaClickStep == 1 && id == CHARTEVENT_MOUSE_MOVE)
   {
      datetime curTime; double curPrice; int subwin = 0;
      if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subwin, curTime, curPrice))
      {
         ObjectDelete(0, PENTAGON_GUIDE_LINE);
         ObjectCreate(0, PENTAGON_GUIDE_LINE, OBJ_TREND, 0, g_p1_time, g_p1_price, curTime, curPrice);
         ObjectSetInteger(0, PENTAGON_GUIDE_LINE, OBJPROP_COLOR, clrYellow);
         ObjectSetInteger(0, PENTAGON_GUIDE_LINE, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, PENTAGON_GUIDE_LINE, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, PENTAGON_GUIDE_LINE, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, PENTAGON_GUIDE_LINE, OBJPROP_SELECTABLE, false);
         ChartRedraw(0);
      }
      return;
   }

   if(g_showPentagon && id == CHARTEVENT_CLICK)
   {
      if(GetTickCount() - g_lastBtnClickTick < 200) return;

      datetime clickTime; double clickPrice; int subwin = 0;
      if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subwin, clickTime, clickPrice))
      {
         if(g_pentaClickStep == 0)
         {
            g_p1_time  = clickTime;
            g_p1_price = clickPrice;
            g_pentaClickStep = 1;
            UpdatePentagonButtonUI();
            ChartRedraw(0);
            return;
         }
         else if(g_pentaClickStep == 1)
         {
            g_p2_time  = clickTime;
            g_p2_price = clickPrice;
            g_pentaClickStep = 2;
            
            RemoveGuideLine();
            UpdatePentagonButtonUI();
            
            CreateBasePentagon(g_p1_time, g_p1_price, g_p2_time, g_p2_price);
            ChartRedraw(0);
            return;
         }
      }
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_showPentagon && StringFind(sparam, PENTAGON_EDGE_PREFIX) == 0)
      {
         AddAdjacentPentagon(sparam);
         ChartRedraw(0);
         return;
      }

      if(sparam == BTN_HIDE)
      {
         g_lastBtnClickTick = GetTickCount();
         g_hideAllPanel = !g_hideAllPanel;
         SetRightUIElementsVisible(!g_hideAllPanel);
         
         ObjectSetString(0, BTN_HIDE, OBJPROP_TEXT, g_hideAllPanel ? "Show" : "Hide");
         ObjectSetInteger(0, BTN_HIDE, OBJPROP_BGCOLOR, g_hideAllPanel ? clrOrangeRed : clrGray);
         ObjectSetInteger(0, BTN_HIDE, OBJPROP_STATE, false);
         ChartRedraw(0);
         return;
      }

      if(sparam == BTN_PENTAGON)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showPentagon = !g_showPentagon;
         
         if(g_showPentagon)
         {
            g_pentaClickStep = 0;
            SetRightUIElementsVisible(false);
         }
         else
         {
            ClearPentagon();
            if(!g_hideAllPanel) SetRightUIElementsVisible(true);
         }

         UpdatePentagonButtonUI();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0);
         return;
      }

      if(StringFind(sparam, BTN_W_FILTER_PREFIX) == 0)
      {
         g_lastBtnClickTick = GetTickCount();
         string idxStr = StringSubstr(sparam, StringLen(BTN_W_FILTER_PREFIX));
         int idx = (int)StringToInteger(idxStr);
         if(idx >= 0 && idx < g_symbolCount)
         {
            g_useWeeklyFilterPerSymbol[idx] = !g_useWeeklyFilterPerSymbol[idx];

            bool state = g_useWeeklyFilterPerSymbol[idx];
            GlobalVariableSet(WeeklyFilterVarName(g_symbols[idx]), state ? 1 : 0);
            ObjectSetString(0, sparam, OBJPROP_TEXT, state ? "W" : "w");
            ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, state ? clrDodgerBlue : clrDimGray);
            ObjectSetInteger(0, sparam, OBJPROP_COLOR, state ? clrWhite : clrLightGray);
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            
            ChartRedraw(0);
            return;
         }
      }

      if(sparam == BTN_BB)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showBB = !g_showBB;
         UpdateMAButtonLook(BTN_BB, "BB", g_showBB, clrCyan);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_WP)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showWP = !g_showWP;
         UpdateMAButtonLook(BTN_WP, "WP", g_showWP, clrGold);
         DrawPivotLines();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_DP)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showDP = !g_showDP;
         UpdateMAButtonLook(BTN_DP, "DP", g_showDP, clrOrange);
         DrawPivotLines();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_WEEKLY)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showWeekly = !g_showWeekly;
         UpdateMAButtonLook(BTN_WEEKLY, "週", g_showWeekly, clrYellow);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_UPPER)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showUpper = !g_showUpper;
         UpdateMAButtonLook(BTN_UPPER, "上", g_showUpper, clrOrangeRed);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_MIDDLE)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showMiddle = !g_showMiddle;
         UpdateMAButtonLook(BTN_MIDDLE, "中", g_showMiddle, clrLime);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }
      if(sparam == BTN_LOWER)
      {
         g_lastBtnClickTick = GetTickCount();
         g_showLower = !g_showLower;
         UpdateMAButtonLook(BTN_LOWER, "下", g_showLower, clrDeepSkyBlue);
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChartRedraw(0); return;
      }

      if(sparam == "MTF_Rank_BestPair")
      {
         g_lastBtnClickTick = GetTickCount();
         if(g_bestPairSymbol != "")
         {
            if(OpenInNewChart)
            {
               long newChartId = ChartOpen(g_bestPairSymbol, _Period);
               if(newChartId == 0) Print("チャートを開けませんでした: ", g_bestPairSymbol);
            }
            else
            {
               bool ok = ChartSetSymbolPeriod(0, g_bestPairSymbol, (ENUM_TIMEFRAMES)_Period);
               if(!ok) Print("通貨ペアの切り替えに失敗しました: ", g_bestPairSymbol);
            }
            ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
            ChartRedraw(0);
         }
         return;
      }

      string prefix = "MTF_Panel_Row_";
      if(StringFind(sparam, prefix) == 0)
      {
         g_lastBtnClickTick = GetTickCount();
         string idxStr = StringSubstr(sparam, StringLen(prefix));
         int idx = (int)StringToInteger(idxStr);
         if(idx >= 0 && idx < g_symbolCount)
         {
            string sym = g_symbols[idx];

            if(OpenInNewChart)
            {
               long newChartId = ChartOpen(sym, _Period);
               if(newChartId == 0) Print("チャートを開けませんでした: ", sym);
            }
            else
            {
               bool ok = ChartSetSymbolPeriod(0, sym, (ENUM_TIMEFRAMES)_Period);
               if(!ok) Print("通貨ペアの切り替えに失敗しました: ", sym);
            }

            ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
            ChartRedraw(0);
         }
      }
   }
}
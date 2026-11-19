// ExitZoneEngine.mqh
// 損切り・利確ゾーン表示エンジン
// 表示だけ。注文は出さない。手動でドラッグして使う。
// 圧縮エンジン本体は触らない。別エンジン。
#property strict

input group "=== 損切り・利確ゾーン ==="
input bool   EXIT_Enable      = true;   // ゾーン表示をする
input double EXIT_SL_ATR_Mult = 1.5;    // 損切り = ATR x 何倍
input double EXIT_TP1_R       = 1.0;    // TP1 = 何R
input double EXIT_TP2_R       = 2.0;    // TP2 = 何R
input bool   EXIT_UseST_Trail = true;   // 入った後、Supertrendで損切りをトレーリングする
input bool   EXIT_ShowZones    = true;   // ゾーン (帯) で表示する (falseなら線だけ)
input color  EXIT_SL_Color     = clrRed;       // 損切りゾーンの色
input color  EXIT_TP1_Color    = clrLime;      // TP1ゾーンの色
input color  EXIT_TP2_Color    = clrDodgerBlue; // TP2ゾーンの色

struct EXIT_Result
  {
   bool   ready;
   int    dir;         // +1=買い -1=売り 0=方向なし
   double entry;       // 基準価格 (今の終値 or ポジションの建値)
   double sl;          // 損切り価格
   double slTop;       // 損切りゾーンの上
   double slBot;       // 損切りゾーンの下
   double tp1;         // TP1価格
   double tp1Top;
   double tp1Bot;
   double tp2;         // TP2価格
   double tp2Top;
   double tp2Bot;
   double oneR;        // 1Rの値幅
   bool   hasPos;      // ポジションを持ってるか
   double posPrice;    // ポジションの建値
  };

// 計算 (現在のチャートの通貨・時間足で計算する)
bool EXIT_Compute(const string symbol, const ENUM_TIMEFRAMES tf, const int dir,
                  const double atr, const double stLine, const double donUpper, const double donLower,
                  EXIT_Result &r)
  {
   r.ready = false;
   r.dir = dir;
   r.entry = 0.0;
   r.sl = 0.0; r.slTop = 0.0; r.slBot = 0.0;
   r.tp1 = 0.0; r.tp1Top = 0.0; r.tp1Bot = 0.0;
   r.tp2 = 0.0; r.tp2Top = 0.0; r.tp2Bot = 0.0;
   r.oneR = 0.0;
   r.hasPos = false;
   r.posPrice = 0.0;

   if(!EXIT_Enable) return false;
   if(dir == 0) return false;
   if(atr <= 0.0) return false;

   double close = iClose(symbol, tf, 1);
   if(close <= 0.0) return false;

   // ポジションを持ってるか確認
   bool hasPos = false;
   double posPrice = 0.0;
   if(PositionSelect(symbol))
     {
      // 同じ通貨のポジションがある
      hasPos = true;
      posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
     }

   // 基準価格：ポジションがあれば建値、なければ今の終値
   double entry = hasPos ? posPrice : close;
   r.entry = entry;
   r.hasPos = hasPos;
   r.posPrice = posPrice;

   // 1R = ATR x 倍率
   double oneR = atr * EXIT_SL_ATR_Mult;
   r.oneR = oneR;

   // ゾーンの半分の幅 = ATRの0.25倍 (帯の厚み)
   double half = atr * 0.25;

   // 損切り：ATRベース
   double slATR = entry - dir * oneR;

   // 入った後で、Supertrendを使う場合
   // 買い：損切りは Supertrendラインの少し下。ただし、建値より下にはしない (建値割れは防ぐ)
   // 売り：損切りは Supertrendラインの少し上。ただし、建値より上にはしない
   double sl = slATR;
   if(hasPos && EXIT_UseST_Trail && stLine > 0.0)
     {
      if(dir > 0)
        {
         // 買い：Supertrendラインの少し下が損切り
         // ただし、ATR損切りより上にしか動かさない (いい方向にだけ動く)
         double slST = stLine - atr * 0.2;
         if(slST > sl) sl = slST;
         // 建値より上に損切りを持っていかない (建値移動は手動でやる)
         if(sl > entry) sl = entry;
        }
      else
        {
         double slST = stLine + atr * 0.2;
         if(slST < sl) sl = slST;
         if(sl < entry) sl = entry;
        }
     }

   r.sl = sl;
   r.slTop = sl + half;
   r.slBot = sl - half;

   // TP1 = 1R
   double tp1 = entry + dir * oneR * EXIT_TP1_R;
   r.tp1 = tp1;
   r.tp1Top = tp1 + half;
   r.tp1Bot = tp1 - half;

   // TP2 = 2R または Donchianバンド (どっちか近い方)
   double tp2ATR = entry + dir * oneR * EXIT_TP2_R;
   double tp2 = tp2ATR;
   if(dir > 0 && donUpper > 0.0)
     {
      // 買い：Donchian上バンドが TP2より手前にあれば、そっちを使う
      if(donUpper > entry && donUpper < tp2ATR) tp2 = donUpper;
     }
   else if(dir < 0 && donLower > 0.0)
     {
      if(donLower < entry && donLower > tp2ATR) tp2 = donLower;
     }
   r.tp2 = tp2;
   r.tp2Top = tp2 + half;
   r.tp2Bot = tp2 - half;

   r.ready = true;
   return true;
  }

// チャートにゾーンを描く
void EXIT_Draw(const EXIT_Result &r)
  {
   // 古いゾーンを消す
   ObjectsDeleteAll(0, "EXIT_Zone_");
   ObjectsDeleteAll(0, "EXIT_Label_");
   if(!r.ready) return;
   if(!EXIT_ShowZones && !EXIT_Enable) return;

   datetime t1 = iTime(_Symbol, _Period, 30);
   datetime t2 = iTime(_Symbol, _Period, 0) + (datetime)(PeriodSeconds(_Period) * 10);
   if(t1 <= 0 || t2 <= 0)
     {
      t1 = TimeCurrent() - (datetime)(PeriodSeconds(_Period) * 30);
      t2 = TimeCurrent() + (datetime)(PeriodSeconds(_Period) * 10);
     }

   // 損切りゾーン
   string slName = "EXIT_Zone_SL";
   ObjectCreate(0, slName, OBJ_RECTANGLE, 0, t1, r.slTop, t2, r.slBot);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, EXIT_SL_Color);
   ObjectSetInteger(0, slName, OBJPROP_FILL, true);
   ObjectSetInteger(0, slName, OBJPROP_BACK, true);
   ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, slName, OBJPROP_HIDDEN, true);

   // TP1ゾーン
   string tp1Name = "EXIT_Zone_TP1";
   ObjectCreate(0, tp1Name, OBJ_RECTANGLE, 0, t1, r.tp1Top, t2, r.tp1Bot);
   ObjectSetInteger(0, tp1Name, OBJPROP_COLOR, EXIT_TP1_Color);
   ObjectSetInteger(0, tp1Name, OBJPROP_FILL, true);
   ObjectSetInteger(0, tp1Name, OBJPROP_BACK, true);
   ObjectSetInteger(0, tp1Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp1Name, OBJPROP_HIDDEN, true);

   // TP2ゾーン
   string tp2Name = "EXIT_Zone_TP2";
   ObjectCreate(0, tp2Name, OBJ_RECTANGLE, 0, t1, r.tp2Top, t2, r.tp2Bot);
   ObjectSetInteger(0, tp2Name, OBJPROP_COLOR, EXIT_TP2_Color);
   ObjectSetInteger(0, tp2Name, OBJPROP_FILL, true);
   ObjectSetInteger(0, tp2Name, OBJPROP_BACK, true);
   ObjectSetInteger(0, tp2Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp2Name, OBJPROP_HIDDEN, true);

   // ラベル
   string dirTxt = (r.dir > 0 ? "買い" : "売り");
   string slLabel = "EXIT_Label_SL";
   ObjectCreate(0, slLabel, OBJ_TEXT, 0, t2, r.sl);
   ObjectSetString(0, slLabel, OBJPROP_TEXT, StringFormat("損切り %.5f (%s)", r.sl, dirTxt));
   ObjectSetInteger(0, slLabel, OBJPROP_COLOR, EXIT_SL_Color);
   ObjectSetInteger(0, slLabel, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, slLabel, OBJPROP_SELECTABLE, false);

   string tp1Label = "EXIT_Label_TP1";
   ObjectCreate(0, tp1Label, OBJ_TEXT, 0, t2, r.tp1);
   ObjectSetString(0, tp1Label, OBJPROP_TEXT, StringFormat("TP1 %.5f (1R)", r.tp1));
   ObjectSetInteger(0, tp1Label, OBJPROP_COLOR, EXIT_TP1_Color);
   ObjectSetInteger(0, tp1Label, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, tp1Label, OBJPROP_SELECTABLE, false);

   string tp2Label = "EXIT_Label_TP2";
   ObjectCreate(0, tp2Label, OBJ_TEXT, 0, t2, r.tp2);
   ObjectSetString(0, tp2Label, OBJPROP_TEXT, StringFormat("TP2 %.5f (2R/Donchian)", r.tp2));
   ObjectSetInteger(0, tp2Label, OBJPROP_COLOR, EXIT_TP2_Color);
   ObjectSetInteger(0, tp2Label, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, tp2Label, OBJPROP_SELECTABLE, false);
  }

// 描画を消す
void EXIT_Clear()
  {
   ObjectsDeleteAll(0, "EXIT_Zone_");
   ObjectsDeleteAll(0, "EXIT_Label_");
  }

// 詳細パネル用のテキスト
string EXIT_Text(const EXIT_Result &r)
  {
   if(!r.ready) return "";
   string dirTxt = (r.dir > 0 ? "買い" : "売り");
   string posTxt = r.hasPos ? " (ポジションあり)" : " (入る前)";
   return StringFormat("[損切り・利確 %s%s] 基準%.5f 損切り%.5f TP1 %.5f TP2 %.5f 1R=%.5f",
                       dirTxt, posTxt, r.entry, r.sl, r.tp1, r.tp2, r.oneR);
  }
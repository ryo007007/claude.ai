// ExitZoneEngine.mqh v3
// スプレッド対応版
// 買い：entry=Ask / 損切り・利確線=Bid (発動はBid)
// 売り：entry=Bid / 損切り・利確線=Ask (発動はAsk)
// 表示だけ。注文は出さない。
#property strict

input group "=== 損切り・利確ゾーン ==="
input bool   EXIT_Enable       = true;         // 損切り・利確を表示リスク1：リワード2以上が良（スキャルピング1：1も可）
input double EXIT_SL_ATR_Mult  = 1.5;          // 損切りまでの距離R（ATRの倍数）NY時間多め
input double EXIT_TP1_R        = 1.0;          // 利確1の距離（近いほう）Rの倍数
double EXIT_TP2_R              = 2.0;          // 利確2までの距離（遠いほう）Rの倍数
input bool   EXIT_UseST_Trail  = true;         // 利益が出たら、利確を伸ばして追う
input bool   EXIT_ShowZones    = true;         // 色の帯で表示する
input bool   EXIT_Debug        = false;        // 確認用のログ出し、確認終了後falseにして軽くする
input color  EXIT_SL_Color     = clrRed;       // 損切りの色（赤）
input color  EXIT_TP1_Color    = clrLime;      // 利確1の色（緑）
input color  EXIT_TP2_Color    = clrDodgerBlue;// 利確2の色（青）

struct EXIT_Result
  {
   bool   ready;
   int    dir;
   double entry;       // 実際に約定する価格 (買い=Ask / 売り=Bid)
   double entryAsk;    // Ask
   double entryBid;    // Bid
   double spread;      // Ask - Bid (価格差)
   double sl;          // 損切り線 = 発動する価格 (買い=Bid / 売り=Ask)
   double slTop;
   double slBot;
   double tp1;         // TP1線 = 発動する価格
   double tp1Top;
   double tp1Bot;
   double tp2;         // TP2線 = 発動する価格
   double tp2Top;
   double tp2Bot;
   double oneR;
   bool   hasPos;
   double posPrice;
  };

bool EXIT_Compute(const string symbol, const ENUM_TIMEFRAMES tf, const int dir,
                  const double atrIn, const double stLine, const double donUpper, const double donLower,
                  EXIT_Result &r)
  {
   r.ready = false;
   r.dir = dir;
   r.entry = 0.0; r.entryAsk = 0.0; r.entryBid = 0.0; r.spread = 0.0;
   r.sl = 0.0; r.slTop = 0.0; r.slBot = 0.0;
   r.tp1 = 0.0; r.tp1Top = 0.0; r.tp1Bot = 0.0;
   r.tp2 = 0.0; r.tp2Top = 0.0; r.tp2Bot = 0.0;
   r.oneR = 0.0; r.hasPos = false; r.posPrice = 0.0;

   if(!EXIT_Enable) { if(EXIT_Debug) Print("[EXIT] Enable=false"); return false; }
   if(dir == 0)     { if(EXIT_Debug) Print("[EXIT] dir=0"); return false; }

   double atr = atrIn;
   if(atr <= 0.0)
     {
      int h = iATR(symbol, tf, 14);
      if(h != INVALID_HANDLE)
        {
         double b[1];
         if(CopyBuffer(h, 0, 1, 1, b) == 1) atr = b[0];
         IndicatorRelease(h);
        }
     }
   if(atr <= 0.0) { if(EXIT_Debug) Print("[EXIT] ATR=0"); return false; }

   // 今の Bid / Ask を取る
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
     {
      // 取れなければ、終値(Bid)で代用
      double c = iClose(symbol, tf, 1);
      if(c <= 0.0) { if(EXIT_Debug) Print("[EXIT] close=0"); return false; }
      bid = c;
      ask = c;
     }
   double spread = MathMax(0.0, ask - bid);
   r.spread = spread;

   // ポジションを持ってるか
   bool hasPos = false;
   double posPrice = 0.0;
   if(PositionSelect(symbol))
     {
      hasPos = true;
      posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
     }
   r.hasPos = hasPos;
   r.posPrice = posPrice;

   // 入値は、方向が決まったときに固定する。毎ティック、今の価格で動かさない
   static int lastLockDir = 0;
   static double lockAsk = 0.0;
   static double lockBid = 0.0;

   double entryAsk = 0.0;
   double entryBid = 0.0;
   double entry = 0.0;

   if(hasPos)
     {
      // ポジションがあるときは、実際の入値を使う
      entryAsk = posPrice;
      entryBid = posPrice;
      entry = posPrice;
      lastLockDir = dir;
      lockAsk = entryAsk;
      lockBid = entryBid;
     }
   else if(dir != lastLockDir || lockAsk <= 0.0)
     {
      // 方向が変わったときだけ、入値を取り直す
      lastLockDir = dir;
      lockAsk = ask;
      lockBid = bid;
     }

   if(dir > 0)
     {
      // 買い：入るのは Ask（固定した入値を使う）
      entryAsk = hasPos ? posPrice : lockAsk;
      entryBid = entryAsk - spread;
      entry = entryAsk;
     }
   else
     {
      // 売り：入るのは Bid（固定した入値を使う）
      entryBid = hasPos ? posPrice : lockBid;
      entryAsk = entryBid + spread;
      entry = entryBid;
     }

   r.entry = entry;
   r.entryAsk = entryAsk;
   r.entryBid = entryBid;

   double oneR = atr * EXIT_SL_ATR_Mult;
   r.oneR = oneR;
   double half = atr * 0.25;

   // 損切り・利確は「発動する側」の価格で計算する
   // 買い：発動は Bid。売り：発動は Ask。
   // Supertrend / Donchian は Bidベースなので、売りの時は spread を足して Ask に直す
   if(dir > 0)
     {
      // 買い：基準は Bid
      double base = entryBid;

      double sl = base - oneR;
      if(hasPos && EXIT_UseST_Trail && stLine > 0.0)
        {
         // STラインは Bidベースなので、そのまま使える
         double slST = stLine - atr * 0.2;
         if(slST > sl) sl = slST;
         if(sl > base) sl = base;
        }
      r.sl = sl; r.slTop = sl + half; r.slBot = sl - half;

      double tp1 = base + oneR * EXIT_TP1_R;
      r.tp1 = tp1; r.tp1Top = tp1 + half; r.tp1Bot = tp1 - half;

      double tp2R = MathMax(2.0, EXIT_TP1_R + 1.0);
      double tp2ATR = base + oneR * tp2R;
      double tp2 = tp2ATR;
      // Donchian上バンドは Bidベースなので、そのまま比べられる
      // ただし、利確1に近すぎたら、Donchianは無視する
      if(donUpper > 0.0 && donUpper > base && donUpper < tp2ATR && donUpper > tp1 + oneR * 0.5) tp2 = donUpper;
      if(tp2 < tp1 + oneR * 0.5) tp2 = tp1 + oneR * 0.5;
      r.tp2 = tp2; r.tp2Top = tp2 + half; r.tp2Bot = tp2 - half;
     }
   else
     {
      // 売り：基準は Ask
      double base = entryAsk;

      double sl = base + oneR;
      if(hasPos && EXIT_UseST_Trail && stLine > 0.0)
        {
         // STラインは Bidベース → Ask に直す
         double stAsk = stLine + spread;
         double slST = stAsk + atr * 0.2;
         if(slST < sl) sl = slST;
         if(sl < base) sl = base;
        }
      r.sl = sl; r.slTop = sl + half; r.slBot = sl - half;

      double tp1 = base - oneR * EXIT_TP1_R;
      r.tp1 = tp1; r.tp1Top = tp1 + half; r.tp1Bot = tp1 - half;

      double tp2R = MathMax(2.0, EXIT_TP1_R + 1.0);
      double tp2ATR = base - oneR * tp2R;
      double tp2 = tp2ATR;
      // Donchian下バンドは Bidベース → Ask に直して比べる
      // ただし、利確1に近すぎたら、Donchianは無視する
      if(donLower > 0.0)
        {
         double donLowerAsk = donLower + spread;
         if(donLowerAsk < base && donLowerAsk > tp2ATR && donLowerAsk < tp1 - oneR * 0.5) tp2 = donLowerAsk;
        }
      if(tp2 > tp1 - oneR * 0.5) tp2 = tp1 - oneR * 0.5;
      r.tp2 = tp2; r.tp2Top = tp2 + half; r.tp2Bot = tp2 - half;
     }

   r.ready = true;
   return true;
  }

void EXIT_Draw(const EXIT_Result &r)
  {
   ObjectsDeleteAll(0, "EXIT_Zone_");
   ObjectsDeleteAll(0, "EXIT_Label_");
   if(!r.ready) return;

   datetime t1 = iTime(_Symbol, _Period, 30);
   datetime t2 = iTime(_Symbol, _Period, 0) + (datetime)(PeriodSeconds(_Period) * 10);
   if(t1 <= 0 || t2 <= 0)
     {
      t1 = TimeCurrent() - (datetime)(PeriodSeconds(_Period) * 30);
      t2 = TimeCurrent() + (datetime)(PeriodSeconds(_Period) * 10);
     }

   string slName = "EXIT_Zone_SL";
   ObjectCreate(0, slName, OBJ_RECTANGLE, 0, t1, r.slTop, t2, r.slBot);
   ObjectSetInteger(0, slName, OBJPROP_COLOR, EXIT_SL_Color);
   ObjectSetInteger(0, slName, OBJPROP_FILL, true);
   ObjectSetInteger(0, slName, OBJPROP_BACK, false);
   ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, slName, OBJPROP_HIDDEN, false);

   string tp1Name = "EXIT_Zone_TP1";
   ObjectCreate(0, tp1Name, OBJ_RECTANGLE, 0, t1, r.tp1Top, t2, r.tp1Bot);
   ObjectSetInteger(0, tp1Name, OBJPROP_COLOR, EXIT_TP1_Color);
   ObjectSetInteger(0, tp1Name, OBJPROP_FILL, true);
   ObjectSetInteger(0, tp1Name, OBJPROP_BACK, false);
   ObjectSetInteger(0, tp1Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp1Name, OBJPROP_HIDDEN, false);

   string tp2Name = "EXIT_Zone_TP2";
   ObjectCreate(0, tp2Name, OBJ_RECTANGLE, 0, t1, r.tp2Top, t2, r.tp2Bot);
   ObjectSetInteger(0, tp2Name, OBJPROP_COLOR, EXIT_TP2_Color);
   ObjectSetInteger(0, tp2Name, OBJPROP_FILL, true);
   ObjectSetInteger(0, tp2Name, OBJPROP_BACK, false);
   ObjectSetInteger(0, tp2Name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tp2Name, OBJPROP_HIDDEN, false);

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

void EXIT_Clear()
  {
   ObjectsDeleteAll(0, "EXIT_Zone_");
   ObjectsDeleteAll(0, "EXIT_Label_");
  }

string EXIT_Text(const EXIT_Result &r)
  {
   if(!r.ready) return "";
   string dirTxt = (r.dir > 0 ? "買い" : "売り");
   string posTxt = r.hasPos ? " (ポジションあり)" : " (入る前)";
   string trigTxt = (r.dir > 0 ? "発動=Bid" : "発動=Ask");
   return StringFormat("[損切り・利確 %s%s %s] 入値%.5f(Ask%.5f/Bid%.5f SP%.5f) 損切り%.5f TP1 %.5f TP2 %.5f 1R=%.5f",
                       dirTxt, posTxt, trigTxt, r.entry, r.entryAsk, r.entryBid, r.spread, r.sl, r.tp1, r.tp2, r.oneR);
  }
// 損切り・利確の並びが正しいかチェック
// 買い：損切り(Bid) < 入値(Bid) < TP1 < TP2 なら正しい
// 売り：TP2 < TP1 < 入値(Ask) < 損切り(Ask) なら正しい
// 方向が0、計算できてない場合は true を返す (そのまま出す)
bool EXIT_IsValid(const EXIT_Result &r)
  {
   if(!r.ready) return true; // 計算できてない = 方向が決まってない → 出す
   if(r.dir == 0) return true;

   if(r.dir > 0)
     {
      // 買い：全部 Bid換算で比べる
      // r.sl / r.tp1 / r.tp2 は Bid。r.entryBid も Bid。
      if(!(r.sl < r.entryBid)) return false;
      if(!(r.entryBid < r.tp1)) return false;
      if(!(r.tp1 < r.tp2)) return false;
      if(!(r.sl < r.tp1)) return false;
      return true;
     }
   else
     {
      // 売り：全部 Ask換算で比べる
      // r.sl / r.tp1 / r.tp2 は Ask。r.entryAsk も Ask。
      if(!(r.tp2 < r.tp1)) return false;
      if(!(r.tp1 < r.entryAsk)) return false;
      if(!(r.entryAsk < r.sl)) return false;
      if(!(r.tp1 < r.sl)) return false;
      return true;
     }
  }
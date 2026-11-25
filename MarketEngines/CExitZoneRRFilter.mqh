//+------------------------------------------------------------------+
//|                                            CExitZoneRRFilter.mqh |
//|  Exit Zone v3 - リスクリワード比フィルタ (育てるリスト 30.10/30.11) |
//|  表示-only。OrderSend / OrderClose は書かない。                    |
//|  使い方: 既存の CExitZoneEngine で TP/SL を計算したあと、        |
//|  このフィルタに entry / tp / sl を渡して、表示してよいか判定する。|
//+------------------------------------------------------------------+
#property copyright "Ryoutarou Kadono"
#property version   "1.00"
#property strict

//--- 入力 (既存インジケーターの入力欄に足す。名前は衝突しないこと) ---
input double Inp_RR_Min       = 1.0;  // 表示する最低 RR (リスク1:リワード N)。スキャルピングなら 1.0、デイトレなら 2.0
input double Inp_RR_Highlight = 3.0;  // 強調する RR (リスク1:リワード 3以上)
input double Inp_RR_Star      = 4.0;  // ★★で強調する RR (リスク1:リワード 4以上)

//--- 表示レベル ---
enum ENUM_RR_LEVEL
{
   RR_HIDDEN    = 0,  // 表示しない (RR不足 / 計算不可)
   RR_NORMAL    = 1,  // 普通に表示
   RR_HIGHLIGHT = 2,  // 強調 (1:3以上)
   RR_STAR      = 3   // ★★強調 (1:4以上)
};

//+------------------------------------------------------------------+
//| RR を計算する。リスク = |entry - sl|、リワード = |tp - entry|    |
//|  売り・買いどちらも距離で計算するので方向は要らない。           |
//|  戻り値: RR。計算できないときは -1.0 を返す。                   |
//+------------------------------------------------------------------+
double RR_Calc(const double entry, const double tp, const double sl)
{
   double risk   = MathAbs(entry - sl);
   double reward = MathAbs(tp - entry);
   if(risk <= 0.0)   return(-1.0); // SLが entry と同じ = リスクが測れない → 表示しない
   if(reward <= 0.0) return(0.0);  // TPが entry と同じ/逆 = 儲からない → RR 0
   return(reward / risk);
}

//+------------------------------------------------------------------+
//| 表示レベルを判定する                                             |
//+------------------------------------------------------------------+
ENUM_RR_LEVEL RR_GetLevel(const double entry, const double tp, const double sl)
{
   double rr = RR_Calc(entry, tp, sl);
   if(rr < 0.0)             return(RR_HIDDEN);    // 計算不可
   if(rr < Inp_RR_Min)     return(RR_HIDDEN);    // 最低ライン未満 → 表示しない
   if(rr >= Inp_RR_Star)   return(RR_STAR);      // 1:4以上
   if(rr >= Inp_RR_Highlight) return(RR_HIGHLIGHT); // 1:3以上
   return(RR_NORMAL);
}

//+------------------------------------------------------------------+
//| 表示してよいかだけが要るとき用                                   |
//+------------------------------------------------------------------+
bool RR_IsVisible(const double entry, const double tp, const double sl)
{
   return(RR_GetLevel(entry, tp, sl) != RR_HIDDEN);
}

//+------------------------------------------------------------------+
//| 表示用のラベル。例: "RR 1:2.5" / "RR 1:4.2 ★★"                  |
//+------------------------------------------------------------------+
string RR_Label(const double entry, const double tp, const double sl)
{
   double rr = RR_Calc(entry, tp, sl);
   if(rr < 0.0) return("RR --");
   ENUM_RR_LEVEL lv = RR_GetLevel(entry, tp, sl);
   string s = StringFormat("RR 1:%.1f", rr);
   if(lv == RR_HIGHLIGHT) s += " 強調";
   if(lv == RR_STAR)      s += " ★★";
   return(s);
}

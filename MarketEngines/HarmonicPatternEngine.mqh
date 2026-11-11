//+------------------------------------------------------------------+
//|                                     HarmonicPatternEngine.mqh    |
//|  ハーモニックパターン検知エンジン（実用版・描画モード切替対応）    |
//|  AB=CD と Gartley パターンに絞って検知します                      |
//+------------------------------------------------------------------+
#property copyright "Harmonic Pattern Engine"
#property version   "1.30"

//--- パターン種別
enum HARM_PATTERN
  {
   HARM_NONE = 0,
   HARM_ABCD,
   HARM_GARTLEY
  };

//--- 描画モード
enum HARM_DRAW_MODE
  {
   HARM_DRAW_FULL = 0,      // すべて表示（デフォルト）
   HARM_DRAW_SHAPE_ONLY,    // 図形のみ（文字ラベル非表示）
   HARM_DRAW_TEXT_ONLY,     // 文字のみ（図形非表示）
   HARM_DRAW_FAINT_SHAPE    // 図形薄く + 文字通常
  };

//--- 検知結果構造体
struct HARM_Result
  {
   bool            found;          // パターン発見フラグ
   HARM_PATTERN    type;           // パターン種別
   int             direction;      // 方向 (1=上昇反転[買い], -1=下降反転[売り], 0=なし)
   double          PRZ;            // 完了予想価格 (Potential Reversal Zone)
   double          X, A, B, C, D;  // 各ポイント価格
   datetime        tX, tA, tB, tC, tD; // 各ポイント時刻
   bool            ready;          // 計算完了フラグ
   string          patternName;    // パターン名（文字列）
  };

//--- 入力パラメータ
input group "=== ハーモニックパターン ==="
input bool   HARM_Enable            = true;   // ハーモニック検知を有にする
input bool   HARM_ShowInList        = true;   // スキャナー一覧に表示する
input bool   HARM_DrawOnChart       = true;   // チャート上に描画する
input int    HARM_LookbackBars      = 150;    // 探索するバー数
input double HARM_Tolerance         = 0.06;   // フィボナッチ比率の許容誤差 (6%)
input int    HARM_SwingSpan         = 5;      // スイング検出の左右バー数
input double HARM_MinSwingATR       = 0.3;    // スイング最小変動幅(ATR倍)
input int    HARM_MaxPatternAgeBars = 30;     // D点がこの本数より古いパターンは無視（追加）

//--- グローバル変数
string g_harmDrawKey = "";

//+------------------------------------------------------------------+
//| 初期化                                                           |
//+------------------------------------------------------------------+
void HARM_Init()
  {
   // 必要に応じて初期化処理
  }

//+------------------------------------------------------------------+
//| ATRを取得                                                        |
//+------------------------------------------------------------------+
double HARM_GetATR(const string symbol, const ENUM_TIMEFRAMES tf, int period=14)
  {
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE) return 0.0;
   if(CopyBuffer(handle, 0, 1, period, atrBuf) <= 0)
     {
      IndicatorRelease(handle);
      return 0.0;
     }
   IndicatorRelease(handle);
   double sum = 0;
   int cnt = ArraySize(atrBuf);
   for(int i = 0; i < cnt; i++) sum += atrBuf[i];
   return (cnt > 0) ? sum / cnt : 0.0;
  }

//+------------------------------------------------------------------+
//| ローカルなHigh/LowからSwing Pointを抽出する（改良版）             |
//+------------------------------------------------------------------+
bool HARM_FindSwings(const string symbol, const ENUM_TIMEFRAMES tf, const int bars,
                     double &prices[], datetime &times[], bool &isHigh[], int &count)
  {
   count = 0;

   int lookback = bars + 20;
   double high[], low[];
   datetime time[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

   if(CopyHigh(symbol, tf, 1, lookback, high) <= 0) return false;
   if(CopyLow(symbol, tf, 1, lookback, low) <= 0) return false;
   if(CopyTime(symbol, tf, 1, lookback, time) <= 0) return false;

   double atr = HARM_GetATR(symbol, tf, 14);
   double minSwing = (atr > 0) ? atr * HARM_MinSwingATR : 0.0001;

   int span = HARM_SwingSpan;
   if(span < 2) span = 2;

   // 一時配列に生のピークを抽出
   double tmpPrices[];
   datetime tmpTimes[];
   bool tmpIsHigh[];
   ArrayResize(tmpPrices, lookback);
   ArrayResize(tmpTimes, lookback);
   ArrayResize(tmpIsHigh, lookback);
   int tmpCount = 0;

   for(int i = span; i < lookback - span; i++)
     {
      bool isPeak = true;
      bool isTrough = true;

      for(int j = 1; j <= span; j++)
        {
         if(high[i] <= high[i-j] || high[i] <= high[i+j]) isPeak = false;
         if(low[i] >= low[i-j] || low[i] >= low[i+j]) isTrough = false;
        }

      if(isPeak)
        {
         tmpPrices[tmpCount] = high[i];
         tmpTimes[tmpCount] = time[i];
         tmpIsHigh[tmpCount] = true;
         tmpCount++;
        }
      else if(isTrough)
        {
         tmpPrices[tmpCount] = low[i];
         tmpTimes[tmpCount] = time[i];
         tmpIsHigh[tmpCount] = false;
         tmpCount++;
        }
     }

   if(tmpCount < 5) return false;

   // 時系列順（古い→新しい）に並び替え
   ArrayReverse(tmpPrices, 0, tmpCount);
   ArrayReverse(tmpTimes, 0, tmpCount);
   ArrayReverse(tmpIsHigh, 0, tmpCount);

   // 同方向連続を排除し、最小変動幅でフィルタ
   ArrayResize(prices, tmpCount);
   ArrayResize(times, tmpCount);
   ArrayResize(isHigh, tmpCount);

   prices[0] = tmpPrices[0];
   times[0] = tmpTimes[0];
   isHigh[0] = tmpIsHigh[0];
   count = 1;

   for(int i = 1; i < tmpCount; i++)
     {
      // 方向が変わったかチェック
      if(tmpIsHigh[i] == isHigh[count - 1])
        {
         // 同方向なら、より極端な値を保持
         if(tmpIsHigh[i] && tmpPrices[i] > prices[count - 1])
           {
            prices[count - 1] = tmpPrices[i];
            times[count - 1] = tmpTimes[i];
           }
         else if(!tmpIsHigh[i] && tmpPrices[i] < prices[count - 1])
           {
            prices[count - 1] = tmpPrices[i];
            times[count - 1] = tmpTimes[i];
           }
         continue;
        }

      // 最小変動幅チェック
      if(MathAbs(tmpPrices[i] - prices[count - 1]) < minSwing)
         continue;

      prices[count] = tmpPrices[i];
      times[count] = tmpTimes[i];
      isHigh[count] = tmpIsHigh[i];
      count++;
     }

   return (count >= 5);
  }

//+------------------------------------------------------------------+
//| フィボナッチ比率のチェック                                        |
//+------------------------------------------------------------------+
bool HARM_CheckFib(double actual, double target, double tolerance)
  {
   if(target == 0.0) return false;
   double ratio = actual / target;
   return (MathAbs(ratio - 1.0) <= tolerance);
  }

//+------------------------------------------------------------------+
//| パターン判定メイン関数（全組み合わせ評価版）                      |
//+------------------------------------------------------------------+
bool HARM_Compute(const string symbol, const ENUM_TIMEFRAMES tf, HARM_Result &res)
  {
   res.found = false;
   res.type = HARM_NONE;
   res.direction = 0;
   res.PRZ = 0.0;
   res.ready = true;
   res.patternName = "";

   double prices[];
   datetime times[];
   bool highs[];
   int count = 0;

   if(!HARM_FindSwings(symbol, tf, HARM_LookbackBars, prices, times, highs, count))
      return false;

   if(count < 5) return false;

   // すべての5点の組み合わせを評価（新しい方から順に試す）
   for(int start = count - 5; start >= 0; start--)
     {
      // High/Lowが交互になっているかチェック
      if(highs[start]   == highs[start+1]) continue; // XとAが同方向はNG
      if(highs[start+1] == highs[start+2]) continue; // AとBが同方向はNG
      if(highs[start+2] == highs[start+3]) continue; // BとCが同方向はNG
      if(highs[start+3] == highs[start+4]) continue; // CとDが同方向はNG

      double X = prices[start];
      double A = prices[start+1];
      double B = prices[start+2];
      double C = prices[start+3];
      double D = prices[start+4];

      datetime tX = times[start];
      datetime tA = times[start+1];
      datetime tB = times[start+2];
      datetime tC = times[start+3];
      datetime tD = times[start+4];

      // D点が古すぎるパターンはスキップ（修正3）
      int dShift = iBarShift(symbol, tf, tD, true);
      if(dShift < 1 || dShift > HARM_MaxPatternAgeBars) continue;

      // 方向性の判定
      bool isBullish = (A > X && B < A && C > B && D < C); // X(Low)->A(High)->B(Low)->C(High)->D(Low)
      bool isBearish = (A < X && B > A && C < B && D > C); // X(High)->A(Low)->B(High)->C(Low)->D(High)

      if(!isBullish && !isBearish)
         continue;

      double XA = MathAbs(A - X);
      double AB = MathAbs(B - A);
      double BC = MathAbs(C - B);
      double CD = MathAbs(D - C);
      double AD = MathAbs(D - X);

      if(XA <= 0 || AB <= 0 || BC <= 0) continue;

      double fibAB = AB / XA;
      double fibBC = BC / AB;
      double fibCD = CD / BC;
      double fibAD = AD / XA;

      HARM_PATTERN detectedType = HARM_NONE;
      double prz = D;

      // 1. AB=CD パターン判定 (AB≒CD かつ BCが0.382~0.786)
      if(HARM_CheckFib(fibCD, fibAB, HARM_Tolerance) &&
         (fibBC >= 0.382 - HARM_Tolerance && fibBC <= 0.786 + HARM_Tolerance))
        {
         detectedType = HARM_ABCD;
         res.patternName = "AB=CD";
        }
      // 2. Gartley パターン判定 (B=0.618XA, C=0.382~0.886AB, D=0.786XA, CD=1.272~1.618BC)
      else if(HARM_CheckFib(fibAB, 0.618, HARM_Tolerance) &&
              (fibBC >= 0.382 - HARM_Tolerance && fibBC <= 0.886 + HARM_Tolerance) &&
              (HARM_CheckFib(fibCD, 1.272, HARM_Tolerance) || HARM_CheckFib(fibCD, 1.618, HARM_Tolerance)) &&
              HARM_CheckFib(fibAD, 0.786, HARM_Tolerance))
        {
         detectedType = HARM_GARTLEY;
         res.patternName = "Gartley";
        }

      if(detectedType != HARM_NONE)
        {
         res.found = true;
         res.type = detectedType;
         res.direction = isBullish ? 1 : -1;
         res.PRZ = prz;
         res.X = X; res.A = A; res.B = B; res.C = C; res.D = D;
         res.tX = tX; res.tA = tA; res.tB = tB; res.tC = tC; res.tD = tD;
         return true;
        }
     }

   return false;
  }

//+------------------------------------------------------------------+
//| スキャナー用の短縮テキスト生成                                   |
//+------------------------------------------------------------------+
string HARM_Text(const HARM_Result &res)
  {
   if(!res.found) return "";
   string dir = (res.direction > 0) ? "↑" : "↓";
   return StringFormat("[%s %s]", res.patternName, dir);
  }

//+------------------------------------------------------------------+
//| 描画モードに応じた色を返す                                       |
//+------------------------------------------------------------------+
color HARM_ShapeColor(color baseColor, HARM_DRAW_MODE mode)
  {
   if(mode == HARM_DRAW_FAINT_SHAPE)
     {
      // 薄くする: 各色を暗めに
      int r = (int)((baseColor >> 16) & 0xFF);
      int g = (int)((baseColor >> 8) & 0xFF);
      int b = (int)(baseColor & 0xFF);
      r = (int)(r * 0.4);
      g = (int)(g * 0.4);
      b = (int)(b * 0.4);
      return (color)((r << 16) | (g << 8) | b);
     }
   return baseColor;
  }

int HARM_ShapeWidth(int baseWidth, HARM_DRAW_MODE mode)
  {
   if(mode == HARM_DRAW_FAINT_SHAPE) return MathMax(1, baseWidth - 1);
   return baseWidth;
  }

//+------------------------------------------------------------------+
//| チャートへの描画（モード切対応版）                             |
//+------------------------------------------------------------------+
void HARM_DrawPattern(const HARM_Result &res, HARM_DRAW_MODE mode=HARM_DRAW_FULL)
  {
   if(!HARM_DrawOnChart || !res.found) return;
   HARM_ClearDrawing();

   bool drawShape = (mode == HARM_DRAW_FULL || mode == HARM_DRAW_SHAPE_ONLY || mode == HARM_DRAW_FAINT_SHAPE);
   bool drawText  = (mode == HARM_DRAW_FULL || mode == HARM_DRAW_TEXT_ONLY || mode == HARM_DRAW_FAINT_SHAPE);
   bool faint     = (mode == HARM_DRAW_FAINT_SHAPE);

   //--- 1. 背景矩形（図形）
   if(drawShape)
     {
      string bgName = "HARM_BG";
      double chartLow = ChartGetDouble(0, CHART_PRICE_MIN);
      double chartHigh = ChartGetDouble(0, CHART_PRICE_MAX);
      if(ObjectCreate(0, bgName, OBJ_RECTANGLE, 0, res.tX, chartHigh, res.tD, chartLow))
        {
         color bgClr;
         if(faint)
            bgClr = (res.direction > 0) ? C'0,15,0' : C'15,0,0';
         else
            bgClr = (res.direction > 0) ? C'0,40,0' : C'40,0,0';
         ObjectSetInteger(0, bgName, OBJPROP_COLOR, bgClr);
         ObjectSetInteger(0, bgName, OBJPROP_BACK, true);
         ObjectSetInteger(0, bgName, OBJPROP_FILL, true);
         ObjectSetInteger(0, bgName, OBJPROP_ZORDER, 1);
         ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
        }
     }

   //--- 2. PRZライン（図形）
   if(drawShape)
     {
      string przName = "HARM_PRZ_Line";
      if(ObjectCreate(0, przName, OBJ_HLINE, 0, 0, res.PRZ))
        {
         color przClr = faint ? C'80,0,80' : clrMagenta;
         ObjectSetInteger(0, przName, OBJPROP_COLOR, przClr);
         ObjectSetInteger(0, przName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, przName, OBJPROP_WIDTH, faint ? 1 : 3);
         ObjectSetInteger(0, przName, OBJPROP_BACK, false);
         ObjectSetInteger(0, przName, OBJPROP_ZORDER, 1000);
         ObjectSetInteger(0, przName, OBJPROP_SELECTABLE, false);
        }
     }

   //--- 3. PRZラベル（文字）
   if(drawText)
     {
      string przLbl = "HARM_PRZ_Label";
      datetime przTime = res.tD + (int)((res.tD - res.tX) * 0.15);
      if(ObjectCreate(0, przLbl, OBJ_TEXT, 0, przTime, res.PRZ))
        {
         string przTxt = StringFormat("  PRZ %s", DoubleToString(res.PRZ, _Digits));
         ObjectSetString(0, przLbl, OBJPROP_TEXT, przTxt);
         ObjectSetInteger(0, przLbl, OBJPROP_COLOR, clrMagenta);
         ObjectSetInteger(0, przLbl, OBJPROP_FONTSIZE, 11);
         ObjectSetInteger(0, przLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
         ObjectSetInteger(0, przLbl, OBJPROP_BACK, false);
         ObjectSetInteger(0, przLbl, OBJPROP_ZORDER, 1001);
         ObjectSetInteger(0, przLbl, OBJPROP_SELECTABLE, false);
        }
     }

   //--- 4. PRZゾーン矩形（図形）- 修正2を適用
   if(drawShape)
     {
      string przZone = "HARM_PRZ_Zone";
      // CDレッグの15%をゾーンの半幅にする
      double zoneHalf = MathAbs(res.C - res.D) * 0.15;
      if(zoneHalf <= 0) zoneHalf = MathAbs(res.X - res.A) * 0.05;
      double przTop = res.PRZ + zoneHalf;
      double przBot = res.PRZ - zoneHalf;
      if(ObjectCreate(0, przZone, OBJ_RECTANGLE, 0, res.tD, przTop, res.tD + (res.tD - res.tX) / 3, przBot))
        {
         color zoneClr = faint ? C'30,0,30' : C'60,0,60';
         ObjectSetInteger(0, przZone, OBJPROP_COLOR, zoneClr);
         ObjectSetInteger(0, przZone, OBJPROP_BACK, true);
         ObjectSetInteger(0, przZone, OBJPROP_FILL, true);
         ObjectSetInteger(0, przZone, OBJPROP_ZORDER, 2);
         ObjectSetInteger(0, przZone, OBJPROP_SELECTABLE, false);
        }
     }

   //--- 5. 各ポイントの円マーカー（図形）とラベル（文字）
   string labels[] = {"X", "A", "B", "C", "D"};
   double p[] = {res.X, res.A, res.B, res.C, res.D};
   datetime t[] = {res.tX, res.tA, res.tB, res.tC, res.tD};
   color pointColors[] = {clrWhite, clrDodgerBlue, clrLime, clrOrange, clrRed};

   for(int i = 0; i < 5; i++)
     {
      // 円マーカー（図形）
      if(drawShape)
        {
         string mrk = "HARM_Marker_" + labels[i];
         if(ObjectCreate(0, mrk, OBJ_ARROW, 0, t[i], p[i]))
           {
            color mrkClr = faint ? HARM_ShapeColor(pointColors[i], mode) : pointColors[i];
            ObjectSetInteger(0, mrk, OBJPROP_ARROWCODE, 159);
            ObjectSetInteger(0, mrk, OBJPROP_COLOR, mrkClr);
            ObjectSetInteger(0, mrk, OBJPROP_WIDTH, faint ? 2 : 3);
            ObjectSetInteger(0, mrk, OBJPROP_BACK, false);
            ObjectSetInteger(0, mrk, OBJPROP_ZORDER, 1000);
            ObjectSetInteger(0, mrk, OBJPROP_SELECTABLE, false);
           }
        }

      // ラベル（文字）
      if(drawText)
        {
         string lbl = "HARM_Label_" + labels[i];
         if(ObjectCreate(0, lbl, OBJ_TEXT, 0, t[i], p[i]))
           {
            ObjectSetString(0, lbl, OBJPROP_TEXT, "  " + labels[i]);
            ObjectSetInteger(0, lbl, OBJPROP_COLOR, pointColors[i]);
            ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 12);
            ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
            ObjectSetInteger(0, lbl, OBJPROP_ZORDER, 1001);
            ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
           }
        }
     }

   //--- 6. 各レッグ（図形）とレッグラベル（文字）
   struct LegInfo { string name; datetime t1; double p1; datetime t2; double p2; };
   LegInfo legs[4];
   legs[0].name="XA"; legs[0].t1=res.tX; legs[0].p1=res.X; legs[0].t2=res.tA; legs[0].p2=res.A;
   legs[1].name="AB"; legs[1].t1=res.tA; legs[1].p1=res.A; legs[1].t2=res.tB; legs[1].p2=res.B;
   legs[2].name="BC"; legs[2].t1=res.tB; legs[2].p1=res.B; legs[2].t2=res.tC; legs[2].p2=res.C;
   legs[3].name="CD"; legs[3].t1=res.tC; legs[3].p1=res.C; legs[3].t2=res.tD; legs[3].p2=res.D;

   color legColors[4] = {clrCyan, clrLime, clrOrange, clrYellow};
   for(int i = 0; i < 4; i++)
     {
      // レッグライン（図形）
      if(drawShape)
        {
         string ln = "HARM_Leg_" + legs[i].name;
         if(ObjectCreate(0, ln, OBJ_TREND, 0, legs[i].t1, legs[i].p1, legs[i].t2, legs[i].p2))
           {
            color lnClr = faint ? HARM_ShapeColor(legColors[i], mode) : legColors[i];
            ObjectSetInteger(0, ln, OBJPROP_COLOR, lnClr);
            ObjectSetInteger(0, ln, OBJPROP_WIDTH, faint ? 1 : 3);
            ObjectSetInteger(0, ln, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, ln, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, ln, OBJPROP_BACK, false);
            ObjectSetInteger(0, ln, OBJPROP_ZORDER, 999);
            ObjectSetInteger(0, ln, OBJPROP_SELECTABLE, false);
           }
        }

      // レッグラベル（文字）
      if(drawText)
        {
         string legLbl = "HARM_LegLbl_" + legs[i].name;
         datetime midT = legs[i].t1 + (int)((legs[i].t2 - legs[i].t1) * 0.5);
         double midP = (legs[i].p1 + legs[i].p2) * 0.5;
         if(ObjectCreate(0, legLbl, OBJ_TEXT, 0, midT, midP))
           {
            ObjectSetString(0, legLbl, OBJPROP_TEXT, "  " + legs[i].name);
            ObjectSetInteger(0, legLbl, OBJPROP_COLOR, legColors[i]);
            ObjectSetInteger(0, legLbl, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, legLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
            ObjectSetInteger(0, legLbl, OBJPROP_BACK, false);
            ObjectSetInteger(0, legLbl, OBJPROP_ZORDER, 1001);
            ObjectSetInteger(0, legLbl, OBJPROP_SELECTABLE, false);
           }
        }
     }

   //--- 7. パターン名ラベル（文字）
   if(drawText)
     {
      string patName = "HARM_PatternName";
      if(ObjectCreate(0, patName, OBJ_TEXT, 0, res.tD, res.D))
        {
         string dirTxt = (res.direction > 0) ? "BUY ↑" : "SELL ↓";
         string txt = StringFormat("  %s  %s", res.patternName, dirTxt);
         ObjectSetString(0, patName, OBJPROP_TEXT, txt);
         ObjectSetInteger(0, patName, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, patName, OBJPROP_FONTSIZE, 13);
         ObjectSetInteger(0, patName, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
         ObjectSetInteger(0, patName, OBJPROP_BACK, false);
         ObjectSetInteger(0, patName, OBJPROP_ZORDER, 1002);
         ObjectSetInteger(0, patName, OBJPROP_SELECTABLE, false);
        }
     }

   //--- 8. X-D の全体トレンドライン（図形）
   if(drawShape)
     {
      string xdLine = "HARM_Line_XD";
      if(ObjectCreate(0, xdLine, OBJ_TREND, 0, res.tX, res.X, res.tD, res.D))
        {
         color xdClr = faint ? C'40,40,40' : clrGray;
         ObjectSetInteger(0, xdLine, OBJPROP_COLOR, xdClr);
         ObjectSetInteger(0, xdLine, OBJPROP_WIDTH, 1);
         ObjectSetInteger(0, xdLine, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, xdLine, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, xdLine, OBJPROP_BACK, true);
         ObjectSetInteger(0, xdLine, OBJPROP_ZORDER, 5);
         ObjectSetInteger(0, xdLine, OBJPROP_SELECTABLE, false);
        }
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| 描画クリア                                                       |
//+------------------------------------------------------------------+
void HARM_ClearDrawing()
  {
   ObjectsDeleteAll(0, "HARM_");
  }
//+------------------------------------------------------------------+
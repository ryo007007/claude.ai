//+------------------------------------------------------------------+
//|                                     HarmonicPatternEngine.mqh    |
//|  ハーモニックパターン検知エンジン（完全版）                        |
//|  Gartley, Bat, Butterfly, AB=CDに対応                              |
//+------------------------------------------------------------------+
#property copyright "Harmonic Pattern Engine"
#property version   "1.00"

//--- パターン種別
enum HARM_PATTERN
  {
   HARM_NONE = 0,
   HARM_GARTLEY,
   HARM_BAT,
   HARM_BUTTERFLY,
   HARM_AB_CD
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
input bool   HARM_Enable       = true;   // ハーモニック検知を有効にする
input bool   HARM_ShowInList   = true;   // スキャナー一覧に表示する
input bool   HARM_DrawOnChart  = true;   // チャート上に描画する
input int    HARM_LookbackBars = 200;    // 探索するバー数
input double HARM_Tolerance    = 0.05;   // フィボナッチ比率の許容誤差 (5%)
input int    HARM_ZigZagDepth  = 12;     // ZigZagの深さ（Swing Point検出用）
input int    HARM_ZigZagDev    = 5;      // ZigZagの偏差（ポイント）
input int    HARM_ZigZagStep   = 3;      // ZigZagのステップ

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
//| ZigZagを用いたSwing Pointの取得                                   |
//| 戻り値: Swing Pointの数                                           |
//+------------------------------------------------------------------+
int HARM_GetSwingPoints(const string symbol, const ENUM_TIMEFRAMES tf, 
                        double &prices[], datetime &times[], bool &isHigh[])
  {
   //--- ZigZagハンドルを作成
   int zzHandle = iCustom(symbol, tf, "Examples\\ZigZag", 
                          HARM_ZigZagDepth, HARM_ZigZagDev, HARM_ZigZagStep);
   if(zzHandle == INVALID_HANDLE)
      return 0;

   //--- ZigZagの値を取得
   double zzBuffer[];
   ArraySetAsSeries(zzBuffer, true);
   int copied = CopyBuffer(zzHandle, 0, 0, HARM_LookbackBars, zzBuffer);
   
   IndicatorRelease(zzHandle);
   
   if(copied <= 0)
      return 0;

   //--- ZigZagの値からSwing Pointを抽出
   ArrayResize(prices, copied);
   ArrayResize(times, copied);
   ArrayResize(isHigh, copied);
   
   int count = 0;
   double lastVal = 0.0;
   
   for(int i = 0; i < copied; i++)
     {
      if(zzBuffer[i] != 0.0 && zzBuffer[i] != lastVal)
        {
         prices[count] = zzBuffer[i];
         times[count] = iTime(symbol, tf, i);
         
         // HighかLowかを判定
         if(count > 0)
            isHigh[count] = (prices[count] > prices[count-1]);
         else
            isHigh[count] = true; // 仮設定
         
         lastVal = zzBuffer[i];
         count++;
        }
     }
   
   ArrayResize(prices, count);
   ArrayResize(times, count);
   ArrayResize(isHigh, count);
   
   return count;
  }

//+------------------------------------------------------------------+
//| フィボナッチ比率のチェック                                        |
//| 戻り値: true=比率が一致                                           |
//+------------------------------------------------------------------+
bool HARM_CheckFibRatio(double actual, double target, double tolerance)
  {
   if(target == 0.0) return false;
   double ratio = actual / target;
   return (MathAbs(ratio - 1.0) <= tolerance);
  }

//+------------------------------------------------------------------+
//| パターン判定メイン関数                                            |
//+------------------------------------------------------------------+
bool HARM_Compute(const string symbol, const ENUM_TIMEFRAMES tf, HARM_Result &res)
  {
   res.found = false;
   res.type = HARM_NONE;
   res.direction = 0;
   res.PRZ = 0.0;
   res.ready = true;
   res.patternName = "";

   //--- Swing Pointを取得
   double swingPrices[];
   datetime swingTimes[];
   bool swingIsHigh[];
   
   int swingCount = HARM_GetSwingPoints(symbol, tf, swingPrices, swingTimes, swingIsHigh);
   
   if(swingCount < 5)
      return false; // ポイントが不足

   //--- 直近の5点(X, A, B, C, D)を抽出
   //--- 下降パターン: X(High) -> A(Low) -> B(High) -> C(Low) -> D(High)
   //--- 上昇パターン: X(Low) -> A(High) -> B(Low) -> C(High) -> D(Low)
   
   for(int start = 0; start <= swingCount - 5; start++)
     {
      double X = swingPrices[start];
      double A = swingPrices[start+1];
      double B = swingPrices[start+2];
      double C = swingPrices[start+3];
      double D = swingPrices[start+4];
      
      datetime tX = swingTimes[start];
      datetime tA = swingTimes[start+1];
      datetime tB = swingTimes[start+2];
      datetime tC = swingTimes[start+3];
      datetime tD = swingTimes[start+4];
      
      //--- 上昇パターンか下降パターンかを判定
      bool isBullish = (A > X && C > A && D < C); // X(Low)->A(High)->B(Low)->C(High)->D(Low)
      bool isBearish = (A < X && C < A && D > C); // X(High)->A(Low)->B(High)->C(Low)->D(High)
      
      if(!isBullish && !isBearish)
         continue;

      //--- 各レッグの長さを計算
      double XA = MathAbs(A - X);
      double AB = MathAbs(B - A);
      double BC = MathAbs(C - B);
      double CD = MathAbs(D - C);
      
      //--- フィボナッチ比率を計算
      double fibAB = AB / XA;
      double fibBC = BC / AB;
      double fibCD = CD / BC;
      double fibAD = MathAbs(D - X) / XA;
      
      //--- パターン判定
      HARM_PATTERN detectedType = HARM_NONE;
      double prz = 0.0;
      
      // 1. Gartley判定
      if(HARM_CheckFibRatio(fibAB, 0.618, HARM_Tolerance) &&
         HARM_CheckFibRatio(fibBC, 0.382, HARM_Tolerance) &&
         HARM_CheckFibRatio(fibCD, 1.272, HARM_Tolerance) &&
         HARM_CheckFibRatio(fibAD, 0.786, HARM_Tolerance))
        {
         detectedType = HARM_GARTLEY;
         // PRZ = D point (0.786 retracement of XA)
         if(isBullish)
            prz = D - (D - X) * 0.05; // 若干のバッファ
         else
            prz = D + (X - D) * 0.05;
        }
      
      // 2. Bat判定
      else if(HARM_CheckFibRatio(fibAB, 0.5, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibBC, 0.5, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibCD, 2.0, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibAD, 0.886, HARM_Tolerance))
        {
         detectedType = HARM_BAT;
         if(isBullish)
            prz = D - (D - X) * 0.05;
         else
            prz = D + (X - D) * 0.05;
        }
      
      // 3. Butterfly判定
      else if(HARM_CheckFibRatio(fibAB, 0.786, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibBC, 0.5, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibCD, 2.618, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibAD, 1.272, HARM_Tolerance))
        {
         detectedType = HARM_BUTTERFLY;
         if(isBullish)
            prz = D - (D - X) * 0.05;
         else
            prz = D + (X - D) * 0.05;
        }
      
      // 4. AB=CD判定
      else if(HARM_CheckFibRatio(fibAB, 1.0, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibBC, 0.5, HARM_Tolerance) &&
              HARM_CheckFibRatio(fibCD, 1.0, HARM_Tolerance))
        {
         detectedType = HARM_AB_CD;
         if(isBullish)
            prz = D - (D - C) * 0.05;
         else
            prz = D + (C - D) * 0.05;
        }
      
      //--- パターンが検出された場合
      if(detectedType != HARM_NONE)
        {
         res.found = true;
         res.type = detectedType;
         res.direction = isBullish ? 1 : -1;
         res.PRZ = prz;
         res.X = X; res.A = A; res.B = B; res.C = C; res.D = D;
         res.tX = tX; res.tA = tA; res.tB = tB; res.tC = tC; res.tD = tD;
         
         switch(detectedType)
           {
            case HARM_GARTLEY:    res.patternName = "Gartley"; break;
            case HARM_BAT:        res.patternName = "Bat"; break;
            case HARM_BUTTERFLY:  res.patternName = "Butterfly"; break;
            case HARM_AB_CD:      res.patternName = "AB=CD"; break;
           }
         
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
//| チャートへの描画                                                 |
//+------------------------------------------------------------------+
void HARM_DrawPattern(const HARM_Result &res)
  {
   if(!HARM_DrawOnChart || !res.found) return;
   
   //--- 既存の描画をクリア
   ObjectsDeleteAll(0, "HARM_");
   
   //--- X-A-B-C-D をラインで結ぶ
   string lineName = "HARM_Line_XABCD";
   ObjectCreate(0, lineName, OBJ_TREND, 0, res.tX, res.X, res.tD, res.D);
   ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, lineName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
   
   //--- PRZ（完了点）に水平線
   string przName = "HARM_PRZ";
   ObjectCreate(0, przName, OBJ_HLINE, 0, 0, res.PRZ);
   ObjectSetInteger(0, przName, OBJPROP_COLOR, clrMagenta);
   ObjectSetInteger(0, przName, OBJPROP_STYLE, STYLE_DASH);
   
   //--- 各ポイントにラベル
   for(int i = 0; i < 5; i++)
     {
      string labelName = "HARM_Label_" + IntegerToString(i);
      double price = 0.0;
      datetime t = 0;
      string label = "";
      
      if(i == 0) { price = res.X; t = res.tX; label = "X"; }
      else if(i == 1) { price = res.A; t = res.tA; label = "A"; }
      else if(i == 2) { price = res.B; t = res.tB; label = "B"; }
      else if(i == 3) { price = res.C; t = res.tC; label = "C"; }
      else if(i == 4) { price = res.D; t = res.tD; label = "D"; }
      
      ObjectCreate(0, labelName, OBJ_TEXT, 0, t, price);
      ObjectSetString(0, labelName, OBJPROP_TEXT, label);
      ObjectSetInteger(0, labelName, OBJPROP_COLOR, clrWhite);
     }
  }

//+------------------------------------------------------------------+
//| 描画クリア                                                       |
//+------------------------------------------------------------------+
void HARM_ClearDrawing()
  {
   ObjectsDeleteAll(0, "HARM_");
  }
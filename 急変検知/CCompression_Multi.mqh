//+------------------------------------------------------------------+
//|                                      CCompression_Multi.mqh       |
//|  CCompression を複数時間足(日足～分足)で同時運用するための管理層  |
//|                                                                    |
//|  1シンボルに対して、D1/H4/M15/M5/M1 のように複数TFのインスタンス  |
//|  を同時に保持・更新する。シンボルを複数にしたい場合は              |
//|  CCOMP_MultiInit を呼ぶ回数を増やすか、配列を2次元的に扱う形で     |
//|  拡張してください(本ファイルは「1シンボル・複数TF」を前提)。      |
//+------------------------------------------------------------------+
#property strict
#include "CCompression.mqh"

CCOMP_Instance g_ccompInstances[];
ENUM_TIMEFRAMES g_ccompTFs[];
int g_ccompTFCount = 0;
string g_ccompSymbol = "";

//+------------------------------------------------------------------+
//| 初期化: 1シンボル × 複数時間足分のインスタンスを作成               |
//+------------------------------------------------------------------+
bool CCOMP_MultiInit(const string symbol, const ENUM_TIMEFRAMES &tfs[], const int tfCount)
  {
   g_ccompSymbol = symbol;
   g_ccompTFCount = tfCount;
   ArrayResize(g_ccompTFs, tfCount);
   ArrayResize(g_ccompInstances, tfCount);

   bool allOk = true;
   for(int i = 0; i < tfCount; i++)
     {
      g_ccompTFs[i] = tfs[i];
      if(!CCOMP_InitInstance(g_ccompInstances[i], symbol, tfs[i]))
         allOk = false;
     }
   return allOk;
  }

//+------------------------------------------------------------------+
//| 終了処理                                                          |
//+------------------------------------------------------------------+
void CCOMP_MultiDeinit()
  {
   for(int i = 0; i < g_ccompTFCount; i++)
      CCOMP_ReleaseInstance(g_ccompInstances[i]);
  }

//+------------------------------------------------------------------+
//| 全時間足を更新。新しい確定足があったTFの数を返す                   |
//+------------------------------------------------------------------+
int CCOMP_MultiUpdate()
  {
   int updated = 0;
   for(int i = 0; i < g_ccompTFCount; i++)
      if(CCOMP_UpdateInstance(g_ccompInstances[i]))
         updated++;
   return updated;
  }

//+------------------------------------------------------------------+
//| 指定時間足のインスタンスを取得                                    |
//+------------------------------------------------------------------+
bool CCOMP_MultiGet(const ENUM_TIMEFRAMES tf, CCOMP_Instance &outInst)
  {
   for(int i = 0; i < g_ccompTFCount; i++)
     {
      if(g_ccompTFs[i] == tf)
        {
         outInst = g_ccompInstances[i];
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| 複数TFが同時にSTRONG/TIGHT COMPRESSION状態にある数を数える         |
//| → 「複数時間足で同時に溜め込んでいる」= より強い警戒シグナル       |
//+------------------------------------------------------------------+
int CCOMP_MultiCountCompressed(const int minScoreState = CCOMP_STRONG_COMPRESSION)
  {
   int cnt = 0;
   for(int i = 0; i < g_ccompTFCount; i++)
     {
      if(!g_ccompInstances[i].ready) continue;
      if((int)g_ccompInstances[i].state >= minScoreState)
         cnt++;
     }
   return cnt;
  }

//+------------------------------------------------------------------+
//| パネル表示用: 全TFの状態を1行テキストにまとめる                   |
//| 例: "D1:TC(7) H4:SC(6) M15:C(4) M5:--(2) M1:--(1)"               |
//+------------------------------------------------------------------+
string CCOMP_MultiSummaryText()
  {
   string s = "";
   for(int i = 0; i < g_ccompTFCount; i++)
     {
      if(i > 0) s += " ";
      string tfName = EnumToString(g_ccompTFs[i]);
      StringReplace(tfName, "PERIOD_", "");
      if(!g_ccompInstances[i].ready)
         s += tfName + ":--";
      else
         s += StringFormat("%s:%s(%d)", tfName, CCOMP_StateShort(g_ccompInstances[i].state), g_ccompInstances[i].score);
     }
   return s;
  }
//+------------------------------------------------------------------+

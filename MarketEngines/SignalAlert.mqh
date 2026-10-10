//+------------------------------------------------------------------+
//|                                              SignalAlert.mqh      |
//|  アラートエンジン                                                  |
//|                                                                    |
//|  ・SAL_Queue() でメッセージをためておき、SAL_Flush() でまとめて送る |
//|    (Push通知は1秒2回・1分10回までの制限があるため、同じ周期に      |
//|     複数のシグナルが出ても1通にまとめて送る)                       |
//|  ・SAL_FireOnce() は、同じシグナルを二重に通知しないための判定。    |
//|    端末のグローバル変数に記録するので、チャートの切替などで         |
//|    インジケーターが読み込み直されても二重通知されない。             |
//+------------------------------------------------------------------+
#property strict

input group "=== アラート設定 ==="
input bool   SAL_UsePopup     = true;        // ポップアップ(Alert)で通知
input bool   SAL_UsePush      = true;        // スマホへPush通知
input bool   SAL_UseSound     = false;       // サウンドを鳴らす
input string SAL_SoundFile    = "alert.wav"; // サウンドファイル名
input bool   SAL_OnTransition = true;        // TRANSITION(圧縮解除)で通知
input bool   SAL_OnSpike      = true;        // 急変で通知

string g_salPending[];

//+------------------------------------------------------------------+
//| 通知メッセージをためる                                             |
//+------------------------------------------------------------------+
void SAL_Queue(const string msg)
  {
   int n = ArraySize(g_salPending);
   ArrayResize(g_salPending, n + 1);
   g_salPending[n] = msg;
  }

//+------------------------------------------------------------------+
//| ためたメッセージをまとめて送信する(毎周期1回呼ぶ)                 |
//+------------------------------------------------------------------+
void SAL_Flush()
  {
   int n = ArraySize(g_salPending);
   if(n == 0)
      return;

   string joined = "";
   for(int i = 0; i < n; i++)
     {
      Print(g_salPending[i]);
      if(SAL_UsePopup)
         Alert(g_salPending[i]);
      if(i > 0)
         joined += " / ";
      joined += g_salPending[i];
     }

   if(SAL_UsePush)
     {
      // Push通知は255文字までなので、超える場合は切り詰める
      if(StringLen(joined) > 250)
         joined = StringSubstr(joined, 0, 247) + "...";
      if(!SendNotification(joined))
         PrintFormat("SAL_Flush: Push通知に失敗しました (error=%d)。MT5のPush設定を確認してください", GetLastError());
     }

   if(SAL_UseSound)
      PlaySound(SAL_SoundFile);

   ArrayResize(g_salPending, 0);
  }

//+------------------------------------------------------------------+
//| 二重通知の防止。stamp(通常は足の時刻)が前回より新しい時だけ true   |
//| key は端末グローバル変数名(63文字以内)                             |
//+------------------------------------------------------------------+
bool SAL_FireOnce(const string key, const double stamp)
  {
   if(GlobalVariableCheck(key))
     {
      double prev = GlobalVariableGet(key);
      if(prev >= stamp)
         return false;
     }
   GlobalVariableSet(key, stamp);
   return true;
  }
//+------------------------------------------------------------------+

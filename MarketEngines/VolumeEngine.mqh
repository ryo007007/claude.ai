//|                                                   VolumeEngine.mqh |
//|  出来高エンジン (Tick Volume)                                       |
//|                                                                    |
//|  ・Tick Volume を、直近20本の平均と比較する                         |
//|  ・3段階: Vol↑ / Vol→ / Vol↓                                       |
//|  ・圧縮エンジン本体は触らない。別エンジン。                          |
//|  ・確定足だけで、毎回過去から計算する(ステートレス)。                |
#property strict

input group "=== 出来高 (Tick Volume) ==="
input bool   VOL_Enable      = true;   // 出来高を計算する
input int    VOL_MA_Bars     = 20;     // 平均に使う本数
input double VOL_UpRatio     = 1.5;    // この倍以上を Vol↑
input double VOL_DownRatio   = 0.8;    // この倍未満を Vol↓
input bool   VOL_ShowInList  = true;   // 一覧に出来高の表示を付ける
input bool   VOL_AlertOnCombo = false; // 圧縮解除 + Vol↑だけで通知する (うるさいので初期OFF)

struct VOL_Result
  {
   bool   ready;
   long   volNow;      // 最新の確定足の Tick Volume
   double volAvg;      // 直近 VOL_MA_Bars 本の平均 (最新足を除く)
   double ratio;       // volNow / volAvg
   int    state;       // +1=Vol↑ 0=Vol→ -1=Vol↓
   int    spikeBars;   // 直近で Vol↑が続いた本数 (0〜)
  };

//| 計算 (最後の確定足の時点の状態を求める)                            |
bool VOL_Compute(const string symbol, const ENUM_TIMEFRAMES tf, VOL_Result &r)
  {
   r.ready = false;
   r.volNow = 0;
   r.volAvg = 0.0;
   r.ratio = 0.0;
   r.state = 0;
   r.spikeBars = 0;

   if(!VOL_Enable)
      return false;

   int need = MathMax(5, VOL_MA_Bars) + 5;
   long vol[];
   ArraySetAsSeries(vol, true);
   int got = CopyTickVolume(symbol, tf, 1, need, vol);
   if(got < need)
      return false;

   long now = vol[0];
   if(now <= 0)
      return false;

   double sum = 0.0;
   int cnt = 0;
   for(int i = 1; i <= VOL_MA_Bars; i++)
     {
      if(vol[i] <= 0) continue;
      sum += (double)vol[i];
      cnt++;
     }
   if(cnt < 5)
      return false;

   double avg = sum / cnt;
   if(avg <= 0.0)
      return false;

   r.volNow = now;
   r.volAvg = avg;
   r.ratio = (double)now / avg;

   if(r.ratio >= VOL_UpRatio)
      r.state = 1;
   else if(r.ratio < VOL_DownRatio)
      r.state = -1;
   else
      r.state = 0;

   // 直近で Vol↑が何本続いたか (最新足から遡る)
   int spike = 0;
   for(int i = 0; i < VOL_MA_Bars; i++)
     {
      double a = 0.0;
      int c2 = 0;
      for(int j = 1; j <= VOL_MA_Bars; j++)
        {
         int idx = i + j;
         if(idx >= got) break;
         if(vol[idx] <= 0) continue;
         a += (double)vol[idx];
         c2++;
        }
      if(c2 < 5) break;
      a /= c2;
      if(a <= 0.0) break;
      double rt = (double)vol[i] / a;
      if(rt >= VOL_UpRatio) spike++;
      else break;
     }
   r.spikeBars = spike;

   r.ready = true;
   return true;
  }

//| 表示・判定・ログ用                                                 |
//--- 一覧に付ける短い表示。表示すべき内容がなければ ""
string VOL_Text(const VOL_Result &r)
  {
   if(!r.ready)
      return "";
   string t = "";
   if(r.state > 0)      t = StringFormat("Vol↑%.1f", r.ratio);
   else if(r.state < 0) t = StringFormat("Vol↓%.1f", r.ratio);
   else                 t = StringFormat("Vol→%.1f", r.ratio);
   if(r.spikeBars >= 2)
      t += StringFormat("(%d本連続)", r.spikeBars);
   return "  [" + t + "]";
  }

//--- 検証ログ用の特徴量 (ASCIIのみ。カンマは使わない)
string VOL_Feat(const VOL_Result &r)
  {
   if(!r.ready)
      return "vol_ready=0";
   return StringFormat("vol_state=%d;vol_ratio=%.2f;vol_now=%I64d;vol_avg=%.1f;vol_spike=%d",
                       r.state, r.ratio, r.volNow, r.volAvg, r.spikeBars);
  }
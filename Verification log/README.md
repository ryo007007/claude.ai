# Verification log(検証用ログ)

`CCompression_Scanner` が出力する検証ログ(CSV)の置き場所です。

- `CCOMP_events.csv` … TRANSITION・急変が出た時点の記録
- `CCOMP_results.csv` … その後 3/6/12 本後にどれだけ動いたか(ATR倍)

CSV は `.gitignore` で除外されているため、GitHub には上がりません。

## 仕組みと設定

MQL5 のプログラムは `MQL5\Files` の外には書き込めません。
そのため、`MQL5\Files\Verification log` から、このフォルダへの
ジャンクション(フォルダのリンク)を作ります。

**インジケーターを初めて動かす前に**、コマンドプロンプトで実行してください。
`<MQL5>` は MT5 の「ファイル → データフォルダを開く」で開く `MQL5` フォルダです。

```
mklink /J "<MQL5>\Files\Verification log" "<MQL5>\Indicators\claude.ai\Verification log"
```

- `MQL5\Files\Verification log` が既に存在する場合は、中身を移してから削除してください(リンクの作成先が存在しているとエラーになります)。
- ログ記録のON/OFFは、チャート右上のボタン、または入力パラメータ `SLG_Enable` で切り替えます。
- 保存先のフォルダ名は入力パラメータ `SLG_Folder` で変更できます。


mklink /J "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Files\Verification log" "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Indicators\claude.ai\Verification log"


次のコマンドを、そのままコピーして貼り付けてください(1行です)。

```
mklink /J "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Files\Verification log" "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Indicators\claude.ai\Verification log"
```

**書き方のルール**
- 形は `mklink /J "リンクを作る場所" "リンク先(実際の置き場所)"` で、順番はこの通りです。
- 1つ目が`Files`側(新しく作られる側)で、2つ目が`Indicators\claude.ai`側(実際のCSVが入る側)です。
- フォルダ名に空白(`Verification log`)があるので、両方の パスをダブルクォート`"`で囲む必要があります。

**実行方法**
1. Windowsのスタートメニューで`cmd`と入力し、「コマンド プロンプト」を開きます。PowerShellではなく、コマンド プロンプトで実行してください(PowerShellだと`mklink`が使えません)。
2. 上のコマンドを貼り付けて、Enterを押します。
3. 成功すると、`...<<===>>...のジャンクションが作成されました`と表示されます。

**エラーが出た場合**
- `既に存在するため、ファイルを作成できません`と出た場合は、`Files`側に`Verification log`フォルダが既にあります。中身が空なら、次のコマンドで削除してから、もう一度`mklink`を実行してください。`/s`は付けないでください(付けると中身ごと消えます)。

  ```
  rmdir "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Files\Verification log"
  ```
  中身が空でないとこのコマンドは失敗するので、安全です。CSVが入っていれば、先に`Indicators\claude.ai\Verification log`へ移してください。
- `指定されたパスが見つかりません`と出た場合は、`Indicators\claude.ai\Verification log`が存在しません。GitHubから取得したフォルダにあるか確認してください。

**確認方法**
次のコマンドを実行し、`Verification log`の行に`<JUNCTION>`と出ればリンクできています。

```
dir "C:\Users\somy0\AppData\Roaming\MetaQuotes\Terminal\2FA8A7E69CED7DC259B1AD86A247F675\MQL5\Files"
```

MT5を開いたままでも作成できます。作成後にスキャナーを動かし、TRANSITIONか急変が出てログが記録されると、`claude.ai\Verification log`の中に`CCOMP_events.csv`ができるはずです。
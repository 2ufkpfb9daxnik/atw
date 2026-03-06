# main.gd ドキュメント

## 概要
`main.gd` はタイピング本体の制御スクリプトです。主に次を担当します。

- メイン画面 UI とショートカット
- ローマ字入力の状態遷移判定（状態機械）
- お題の先読み生成
- 計測タイマーと開始前カウントダウン
- 結果オーバーレイ表示
- 記録の保存（`user://records/records.jsonl`）
- アプリ設定の保存（`user://app_settings.json`）
- 背景画像・背景動画の読み込み

このスクリプトは `Node` にアタッチされ、`main_ui` 配下の UI を名前検索 (`ui_node`) で取得して更新します。

## 関連ファイル
- レイアウト定義: `res://layouts/qwerty_romaji.json`
- お題ファイル: `res://odai/default.txt`
- 記録保存先: `user://records/records.jsonl`
- アプリ設定保存先: `user://app_settings.json`

## 初期化フロー (`_ready`)
起動時は次の順で初期化します。

1. ボタンやオプションのシグナル接続
2. `Records` / `Result` ノードの初期非表示
3. レイアウト JSON 読み込みと遷移テーブル構築
4. ストリーム初期化 (`init_stream`)
5. 結果オーバーレイ生成
6. レイアウト・お題・背景のファイルダイアログ構築
7. タイマーモード、カウントダウン、フォントサイズ UI 構築
8. ラベル類更新、ロック状態更新、背景表示設定
9. アプリ設定読み込み（背景復元）

## 入力仕様 (`_input`)
優先度の高い順で処理します。

1. `main_ui` が非表示なら入力無視
2. 結果オーバーレイ表示中は `Space` で閉じるのみ
3. `Esc` は常に `reset_prompts()` を呼ぶ
4. 非計測時のみショートカット有効
- `R`: 記録画面
- `E`: 終了
- `L`: 配列変更
- `O`: お題変更
5. 非計測・非カウントダウン時の `Space` で開始
6. 計測中のキーは小文字化して `check_input` へ

## 主要状態
### 計測状態
- `timer_running`: 計測中
- `countdown_running`: 開始前カウントダウン中
- `time_left_sec`: 計測残り秒
- `countdown_left_sec`: カウントダウン残り秒
- `round_start_msec`: 計測開始時刻

### 入力ストリーム状態
- `kana_stream`: 入力判定に使うかな列
- `kanji_stream`: 画面表示用文字列
- `kana_to_kanji`: かなカーソルから表示カーソルへの対応
- `chunks`: 文ごとの範囲情報
- `stream_cursor`: 現在かな位置
- `current_state`: 現在の遷移状態
- `typed_history`: 正解キー履歴
- `miss_count`: ミス回数
- `typed_target_chars`: 実入力文字数（区切り記号 `␣` は除外）

### 記録・再現用
- `input_events`: 計測中のキーイベント配列
- `used_odai_unique_lines`: その回で使ったお題ユニーク行
- `used_odai_line_order`: お題出現順（ユニーク配列の index）

## 入力判定（状態機械）
### テーブル構築
`build_table(rules)` が JSON ルール配列を次形式に変換します。

- `table[state][input] = { "output": ..., "next": ... }`

変換時の要点:
- `input` は小文字化
- `output` のカタカナはひらがなへ正規化
- すべての状態に `Space` 遷移を補完

### 1キー判定 (`check_input`)
1. 先読み補充 (`ensure_lookahead`)
2. 状態にキー遷移があるか確認
3. 遷移 `output` が現在カーソルの `kana_stream` と一致するか確認
4. 遷移後に詰み状態にならないか (`can_type_text_from`) を確認
5. 成功なら `on_correct`、失敗なら `on_miss`
6. 計測中なら `input_events` に詳細ログを記録

イベント reason の主な値:
- `ok`
- `invalid_transition`
- `output_mismatch`
- `dead_end`

## お題処理
### フォーマット
想定する記法は `[漢字](かな)` です。`validate_odai_line` が以下を検証します。

- `[]` / `()` の対応
- `]` の直後が `(`
- 空の `[]` や `()` を禁止
- ルビなし漢字を禁止

### 文字列分解
`make_sentence_data` が次を生成します。

- `kanji_text`: 表示用
- `kana_text`: 入力判定用
- `map`: かな各文字が表示のどこに対応するか

### 先読み
`ensure_lookahead` が `LOOKAHEAD_KANA` 以上になるまで文を追加します。

## ラウンド制御
### 開始
`start_round()`:
- 結果オーバーレイを閉じる
- 先読み補充
- カウントダウン秒を取得
- 必要ならカウントダウン開始、不要なら即 `begin_measurement`
- 設定 UI をロック

### 更新
`update_timer(delta)`:
- カウントダウン中は `countdown_left_sec` を減算
- 計測中は `time_left_sec` を減算
- 0 到達で `finish_round(true)`

### 終了
`finish_round(time_up, reset_after_finish=true)`:
- `chars` / `misses` / `score` を算出
- 計測状態解除
- UI 復帰
- `time_up=true` のとき記録保存と結果表示
- `reset_after_finish=true` なら入力状態を初期化

`Esc` 停止時は `finish_round(false, false)` を通るため、時間切れ扱いでは保存しません。

## 記録保存フォーマット
`save_record` が 1行 JSON（JSONL）で保存します。主な項目:

- `record_id`
- `created_at`
- `typed_chars`
- `miss_count`
- `score`
- `measured_seconds`
- `odai_path`
- `layout_path`
- `round_seconds`
- `countdown_seconds`
- `input_events`
- `odai_snapshot.unique_lines`
- `odai_snapshot.line_order`

## 背景機能
### 適用入口
- `_on_change_background_button_pressed`
- `_on_background_file_selected`
- `apply_background_file`

### 画像
`apply_background_image_file`:
- `Image.load(path)` を優先
- 必要なら `load(path)` も試行
- 成功時 `background_texture` に反映

### 動画
`apply_background_video_file`:
- `ResourceLoader.load` で `VideoStream` 読み込み
- 必要なら `VideoStreamTheora` をフォールバック
- `background_video` に設定して再生
- `finished` シグナルで再生再開フォールバック

### 永続化
- 保存: `save_app_settings`
- 復元: `load_app_settings`

## UI 更新モデル
`refresh_ui` が次を更新します。

- `target_text`（現在文）
- `target_text2`（次文）
- `target_text3`（流れる表示）
- `hiragana_box`
- `history_box`
- キャレット位置に合わせた横位置調整

色分け:
- 過去: グレー
- 現在: シアン
- ミス点灯中の現在: 赤
- 未来: 白

## 主要関数の入口
- ライフサイクル: `_ready`, `_process`, `_input`
- 計測: `start_round`, `begin_measurement`, `update_timer`, `finish_round`
- 判定: `check_input`, `on_correct`, `on_miss`, `can_type_text_from`
- ストリーム: `init_stream`, `reset_state`, `ensure_lookahead`
- 保存: `save_record`, `save_app_settings`, `load_app_settings`
- 背景: `apply_background_file`, `apply_background_image_file`, `apply_background_video_file`

## 注意点
- レコード項目を変更すると `records.gd` 側の読み取りも同時修正が必要です。
- UI ノード名を変更した場合は `ui_node` で参照している箇所が影響を受けます。
- 動画形式の対応可否は OS / 実行環境のコーデックに依存します。

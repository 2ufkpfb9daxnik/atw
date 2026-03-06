# records.gd ドキュメント

## 概要
`records.gd` は記録画面全体を制御するスクリプトです。次の 3 モードを持ちます。

- 一覧モード: 全記録の表表示
- 詳細モード: 1件の記録の詳細、リプレイ、入力間隔グラフ
- 評価モード: 集計統計と推移グラフ

データソースは `user://records/records.jsonl` です。`main.gd` が保存した記録を読み取り、表示・分析します。

## 画面構成
`_ready` で動的に UI を組み立てます。

- `build_list_ui`
- `build_detail_ui`
- `build_analytics_ui`

モード切替用ルート:
- `list_scroll`
- `detail_root`
- `analytics_root`

切替関数:
- `show_list_mode`
- `show_detail_mode(rec)`
- `show_analytics_mode`

## ショートカット
`_unhandled_input` でモード別に処理します。

一覧モード:
- `B`: メインへ戻る
- `A`: 評価画面へ

詳細モード:
- `V`: 一覧へ戻る
- `Space`: 再生/停止トグル
- `J`: 再生位置を 1 つ戻す
- `L`: 再生位置を 1 つ進める

評価モード:
- `V`: 一覧へ戻る

`update_records_shortcut_labels` がボタン文言を状態に合わせて更新します。

## 記録ファイルの読み書き
### 読み込み
`load_records_jsonl`:
- JSONL を 1 行ずつ読み込み
- JSON パース失敗行はスキップ
- 返り値は新しい順（reverse 後）

### 保存
`save_records_jsonl(records_newest_first)`:
- ディレクトリを確保
- 古い順で書き戻し

### 同一判定
`is_same_record(a, b)`:
- `record_id` があれば最優先で比較
- ない場合は日時・スコア・入力数・ミス数・パス・イベント数で比較

削除処理 `_on_delete_pressed` は対象 1 件を除いた配列で再保存します。

## 一覧モード
入口: `refresh_records_list`

処理:
1. 表示をクリア
2. ヘッダ追加 (`add_header_row`)
3. 記録読み込み
4. 各レコード行を追加 (`add_record_row`)

主な列:
- 日時
- スコア
- 計測秒
- スコア/秒
- 入力文字
- ミス数
- ミス率
- お題ファイル
- 配列ファイル
- 操作（詳細/削除）

秒数算出は `get_record_seconds` が担当し、優先順は次です。

1. `measured_seconds`
2. `round_seconds`
3. 最終 `input_events[].t_ms`

## 詳細モード
入口: `_on_detail_pressed` -> `show_detail_mode(rec)`

同時に以下を更新します。
- 記録情報 (`fill_detail_info`)
- お題復元 (`fill_detail_odai`)
- リプレイログ初期化 (`reset_replay_log`)
- 入力間隔グラフ (`fill_interval_graph`)

### 記録情報
表示する主項目:
- `created_at`, `record_id`
- スコア、計測秒、スコア/秒
- 入力文字数、ミス数、ミス率
- `odai_path`, `layout_path`
- `round_seconds`, `countdown_seconds`
- 入力イベント数

### お題復元
`reconstruct_odai_lines(rec)` が `odai_snapshot` から順序付きで復元します。

- `unique_lines`
- `line_order`

## リプレイ機能
状態変数:
- `replay_running`
- `replay_events`
- `replay_index`
- `replay_start_msec`

### 再生開始/停止
- `start_replay(true)`: 先頭から
- `start_replay(false)`: 現在位置から再開
- `stop_replay(...)`: 停止
- `toggle_replay_by_space`: Space 用トグル

`_process` で時刻差を見ながらイベントを順次消化します。

- ログ行追加 (`append_replay_event_line`)
- スナップショット更新 (`update_replay_snapshot_preview`)
- グラフマーカー更新 (`set_graph_current_index`)

### 手動シーク
- `seek_replay_to_index`
- `move_replay_cursor`
- `get_current_replay_event_index`

## 入力間隔グラフ（詳細モード）
目的:
- 連続打鍵間隔（ms）を可視化

生成手順:
1. `build_intervals_ms(events)` で間隔列作成
2. `redraw_graph()` で折れ線・軸・マーカー描画

特徴:
- Y軸: 前入力からの経過 ms
- X軸: 入力順
- 横方向ズーム対応
- 再生中は現在位置へ自動スクロール
- クリック/ドラッグで再生位置を移動

ズーム関連:
- `_on_graph_zoom_in_pressed`
- `_on_graph_zoom_out_pressed`
- `_on_graph_zoom_reset_pressed`

現在位置統計 (`update_replay_stats_label`):
- スコア
- スコア/秒
- 文字/秒
- ミス数
- ミス率

## 評価モード
入口: `_on_eval_button_pressed` -> `show_analytics_mode`

2 つの出力を作成します。
- テキスト集計 (`fill_analytics_summary`)
- 推移グラフ (`fill_analytics_trend_graph`)

### 集計内容
- 記録件数、期間
- 合計/平均スコア
- 合計/平均入力文字
- 合計/平均ミス
- 平均スコア/秒
- 平均文字/秒
- 平均ミス率
- 最高/最低スコア
- 配列ファイル使用回数
- お題ファイル使用回数
- 日別回数と平均スコア
- 直近 10 件の要約

### 推移グラフ
時系列（古い -> 新しい）で 3 系列を表示:
- 青: スコア
- 黄: スコア/秒
- 赤: ミス率（%）

各系列は独立した最大値で正規化して描画します。

## records.gd が想定する記録スキーマ
主に参照するキー:
- `record_id`
- `created_at`
- `typed_chars`
- `miss_count`
- `score`
- `measured_seconds`
- `round_seconds`
- `countdown_seconds`
- `odai_path`
- `layout_path`
- `input_events`
- `odai_snapshot.unique_lines`
- `odai_snapshot.line_order`

不足項目があっても、可能な範囲でフォールバックして表示します。

## 主要関数一覧
- ライフサイクル: `_ready`, `_process`, `_on_visibility_changed`
- モード切替: `show_list_mode`, `show_detail_mode`, `show_analytics_mode`
- 読み書き: `load_records_jsonl`, `save_records_jsonl`, `is_same_record`
- 一覧: `refresh_records_list`, `add_header_row`, `add_record_row`
- 詳細: `fill_detail_info`, `fill_detail_odai`, `reset_replay_log`
- リプレイ: `start_replay`, `stop_replay`, `seek_replay_to_index`
- グラフ: `fill_interval_graph`, `redraw_graph`, `set_graph_current_index`
- 評価: `fill_analytics_summary`, `fill_analytics_trend_graph`

## 注意点
- 記録スキーマ変更時は `main.gd` と同時に調整してください。
- リプレイの再現度は `input_events` とスナップショット保存の有無に依存します。
- JSONL の一部行が壊れていても、その行だけ読み飛ばして継続します。

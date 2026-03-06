extends Node

@export var max_items := 10

const MISS_FLASH_TIME := 0.15
const LOOKAHEAD_KANA := 30
const LAYOUT_PATH := "res://layouts/qwerty_romaji.json"
const ODAI_PATH := "res://odai/default.txt"
const DEFAULT_ROUND_TIME_SEC := 60.0
const TIMER_MODE_1MIN := 0
const TIMER_MODE_1HOUR := 1
const TIMER_MODE_CUSTOM := 2
const RECORDS_DIR := "user://records"
const RECORDS_FILE_PATH := "user://records/records.jsonl"
const APP_SETTINGS_PATH := "user://app_settings.json"

var miss_timer := 0.0
var current_layout_path := LAYOUT_PATH
var current_odai_path := ODAI_PATH
var current_background_path := ""
var layout_file_dialog: FileDialog
var odai_file_dialog: FileDialog
var background_file_dialog: FileDialog
var last_layout_validation_error := ""
var last_odai_validation_error := ""

var odai_lines: Array[String] = []
var sentence_cache: Dictionary = {}
var table: Dictionary = {}

var kana_stream := ""
var kanji_stream := ""
var kana_to_kanji: Array[int] = [0]
var chunks: Array[Dictionary] = []

var stream_cursor := 0
var current_state := "default"
var typed_history := ""
var key_timestamps: Array[float] = []
var miss_count := 0
var timer_running := false
var time_left_sec := DEFAULT_ROUND_TIME_SEC
var countdown_running := false
var countdown_left_sec := 0.0
var target_flow_caret_child_index := 0
var hiragana_caret_child_index := 0
var history_caret_child_index := 0
var hira_target_x := 0.0
var history_target_x := 0.0
var smooth_follow_initialized := false
const INPUT_BOX_FOLLOW_SPEED := 14.0
var typed_target_chars := 0
var result_overlay: Control
var result_value_chars_label: Label
var result_value_miss_label: Label
var result_value_score_label: Label
var round_start_msec := 0
var input_events: Array[Dictionary] = []
var used_odai_unique_lines: Array[String] = []
var used_odai_line_order: Array[int] = []
var ui_font_size := 25
var current_background_is_video := false

# main_ui 配下のノードを名前で再帰検索して返す。
func ui_node(name: String) -> Node:
	var ui_root := get_node_or_null("main_ui")
	if ui_root != null:
		var found := ui_root.find_child(name, true, false)
		if found != null:
			return found
	return find_child(name, true, false)

# main_ui 配下に指定名ノードが存在するか返す。
func has_ui_node(name: String) -> bool:
	return ui_node(name) != null

# ノード初期化とボタン接続、入力テーブル構築、初期ストリーム生成を行う。
func _ready() -> void:
	randomize()
	var exit_button := ui_node("exit_button") as Button
	if exit_button != null:
		exit_button.pressed.connect(_on_exit_button_pressed)
	var records_button := ui_node("records_button") as Button
	if records_button != null:
		records_button.pressed.connect(_on_records_button_pressed)
	if has_ui_node("change_layout"):
		(ui_node("change_layout") as Button).pressed.connect(_on_change_layout_button_pressed)
	if has_ui_node("change_odai"):
		(ui_node("change_odai") as Button).pressed.connect(_on_change_odai_button_pressed)
	if has_ui_node("change_background"):
		(ui_node("change_background") as Button).pressed.connect(_on_change_background_button_pressed)
	if has_ui_node("start_button"):
		(ui_node("start_button") as Button).pressed.connect(_on_start_button_pressed)
	if has_ui_node("timer_mode_option"):
		(ui_node("timer_mode_option") as OptionButton).item_selected.connect(_on_timer_mode_option_item_selected)
	if has_ui_node("custom_time_spinbox"):
		(ui_node("custom_time_spinbox") as SpinBox).value_changed.connect(_on_custom_time_spinbox_value_changed)
	if has_ui_node("countdown_spinbox"):
		(ui_node("countdown_spinbox") as SpinBox).value_changed.connect(_on_countdown_spinbox_value_changed)
	
	if has_node("Records"):
		$Records.visible = false
	if has_node("Result"):
		$Result.visible = false
	
	var rules := load_json_array(current_layout_path)
	table = build_table(rules)
	init_stream()
	setup_result_overlay()
	setup_layout_file_dialog()
	setup_odai_file_dialog()
	setup_background_file_dialog()
	update_layout_label()
	update_odai_label()
	update_background_label()
	setup_timer_mode_option()
	setup_countdown_spinbox()
	setup_font_size_spinbox()
	if has_ui_node("font_size_spinbox"):
		(ui_node("font_size_spinbox") as SpinBox).value_changed.connect(_on_font_size_spinbox_value_changed)
	update_custom_time_visibility()
	apply_ui_font_size()
	update_timer_label()
	update_measure_label()
	update_timer_locked_buttons()
	update_main_shortcut_labels()
	apply_background_texture_settings()
	configure_background_video_player()
	load_app_settings()

# メイン画面の操作ボタン文言にショートカット表記を付ける。
func update_main_shortcut_labels() -> void:
	var records_btn := ui_node("records_button") as Button
	if records_btn != null:
		records_btn.text = "記録(R)"
	var start_btn := ui_node("start_button") as Button
	if start_btn != null:
		start_btn.text = "開始"
	var exit_btn := ui_node("exit_button") as Button
	if exit_btn != null:
		exit_btn.text = "終了(E)"
	var layout_btn := ui_node("change_layout") as Button
	if layout_btn != null:
		layout_btn.text = "配列変更(L)"
	var odai_btn := ui_node("change_odai") as Button
	if odai_btn != null:
		odai_btn.text = "お題変更(O)"
	var bg_btn := ui_node("change_background") as Button
	if bg_btn != null:
		bg_btn.text = "背景画像変更"
	update_start_button_shortcut_label()

# Space で開始可能な状態のときだけ開始ボタン文言にショートカットを付ける。
func update_start_button_shortcut_label() -> void:
	if not has_ui_node("start_button"):
		return
	var start_btn := ui_node("start_button") as Button
	if start_btn == null:
		return
	if timer_running:
		start_btn.text = "計測停止(Esc)"
		return
	if can_start_round_by_space():
		start_btn.text = "開始(Space)"
	else:
		start_btn.text = "開始"

# Space で計測開始できる条件を返す。
func can_start_round_by_space() -> bool:
	if not $main_ui.visible:
		return false
	if timer_running or countdown_running:
		return false
	if result_overlay != null and result_overlay.visible:
		return false
	return true

# ミス表示用タイマーを減算し、期限切れで表示を更新する。
func _process(delta: float) -> void:
	update_timer(delta)
	update_input_boxes_smooth(delta)

	if miss_timer > 0.0:
		miss_timer -= delta
		if miss_timer <= 0.0:
			miss_timer = 0.0
			refresh_ui()

# キー入力を受け取り、1文字入力として判定処理に渡す。
func _input(event: InputEvent) -> void:
	if not $main_ui.visible:
		return
	if result_overlay != null and result_overlay.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			var overlay_key := event as InputEventKey
			if overlay_key.unicode == 32:
				hide_result_overlay()
		return
	
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey

		# ESC always resets prompts regardless of measurement state.
		if key_event.keycode == KEY_ESCAPE:
			reset_prompts()
			return

		# 非計測時のみ、メイン操作ショートカットを有効化。
		if not timer_running and not countdown_running:
			if key_event.keycode == KEY_R:
				_on_records_button_pressed()
				return
			if key_event.keycode == KEY_E:
				_on_exit_button_pressed()
				return
			if key_event.keycode == KEY_L:
				_on_change_layout_button_pressed()
				return
			if key_event.keycode == KEY_O:
				_on_change_odai_button_pressed()
				return

		# Space starts countdown/measurement when idle.
		if not timer_running:
			if countdown_running:
				return
			if key_event.unicode == 32:
				start_round()
			return

		var input_candidates := build_input_candidates_from_key_event(key_event)
		if input_candidates.is_empty():
			return
		check_input_candidates(input_candidates)

# 1つのキーイベントから入力候補トークンを生成する（例: "a", "shift+0"）。
func build_input_candidates_from_key_event(key_event: InputEventKey) -> Array[String]:
	var candidates: Array[String] = []

	if key_event.unicode != 0:
		append_unique_input_candidate(candidates, String.chr(key_event.unicode).to_lower())

	var key_text := OS.get_keycode_string(key_event.keycode).strip_edges()
	if not key_text.is_empty():
		var lowered := key_text.to_lower()
		append_unique_input_candidate(candidates, lowered)
		if key_event.shift_pressed:
			append_unique_input_candidate(candidates, "shift+" + lowered)

	var label_text := OS.get_keycode_string(key_event.key_label).strip_edges()
	if not label_text.is_empty():
		var lowered_label := label_text.to_lower()
		append_unique_input_candidate(candidates, lowered_label)
		if key_event.shift_pressed:
			append_unique_input_candidate(candidates, "shift+" + lowered_label)

	return candidates

# 入力候補配列に重複しないトークンを追加する。
func append_unique_input_candidate(candidates: Array[String], token: String) -> void:
	if token.is_empty():
		return
	if not candidates.has(token):
		candidates.append(token)

# お題ストリームを初期化し、表示を先頭状態へ戻す。
func reset_prompts() -> void:
	if timer_running or countdown_running:
		finish_round(false, false)
	hide_result_overlay()
	reset_state()
	ensure_lookahead()
	refresh_ui()

# 終了ボタン押下時にアプリを終了する。
func _on_exit_button_pressed() -> void:
	get_tree().quit()

# 記録画面へ切り替える。
func _on_records_button_pressed() -> void:
	$main_ui.visible = false
	if has_node("Records"):
		$Records.visible = true

# 配列変更ボタン押下でレイアウト選択ダイアログを開く。
func _on_change_layout_button_pressed() -> void:
	if layout_file_dialog == null:
		setup_layout_file_dialog()
	if layout_file_dialog == null:
		return
	layout_file_dialog.current_dir = get_dialog_initial_dir(current_layout_path)
	layout_file_dialog.popup_centered_ratio(0.7)

# お題変更ボタン押下でお題選択ダイアログを開く。
func _on_change_odai_button_pressed() -> void:
	if odai_file_dialog == null:
		setup_odai_file_dialog()
	if odai_file_dialog == null:
		return
	odai_file_dialog.current_dir = get_dialog_initial_dir(current_odai_path)
	odai_file_dialog.popup_centered_ratio(0.7)

# 設定ダイアログの初期ディレクトリを返す。
func get_dialog_initial_dir(current_path: String) -> String:
	if current_path.is_empty():
		return ProjectSettings.globalize_path("res://")
	if current_path.begins_with("res://") or current_path.begins_with("user://"):
		var global := ProjectSettings.globalize_path(current_path)
		if not global.is_empty():
			return global.get_base_dir()
	return current_path.get_base_dir()

# 背景画像変更ボタン押下で画像選択ダイアログを開く。
func _on_change_background_button_pressed() -> void:
	if background_file_dialog == null:
		setup_background_file_dialog()
	if background_file_dialog == null:
		return
	background_file_dialog.popup_centered_ratio(0.7)

# レイアウト選択用のファイルダイアログを生成・設定する。
func setup_layout_file_dialog() -> void:
	if layout_file_dialog != null:
		return

	layout_file_dialog = FileDialog.new()
	layout_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	layout_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	layout_file_dialog.use_native_dialog = true
	layout_file_dialog.title = "配列を選択"
	layout_file_dialog.current_dir = get_dialog_initial_dir(current_layout_path)
	layout_file_dialog.add_filter("*.json", "JSON Layout")
	layout_file_dialog.file_selected.connect(_on_layout_file_selected)
	add_child(layout_file_dialog)

# お題選択用のファイルダイアログを生成・設定する。
func setup_odai_file_dialog() -> void:
	if odai_file_dialog != null:
		return

	odai_file_dialog = FileDialog.new()
	odai_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	odai_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	odai_file_dialog.use_native_dialog = true
	odai_file_dialog.title = "お題ファイルを選択"
	odai_file_dialog.current_dir = get_dialog_initial_dir(current_odai_path)
	odai_file_dialog.add_filter("*.txt", "Text Odai")
	odai_file_dialog.file_selected.connect(_on_odai_file_selected)
	add_child(odai_file_dialog)

# 背景画像選択用のファイルダイアログを生成・設定する。
func setup_background_file_dialog() -> void:
	if background_file_dialog != null:
		return

	background_file_dialog = FileDialog.new()
	background_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	background_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	background_file_dialog.use_native_dialog = true
	background_file_dialog.title = "背景画像を選択"
	background_file_dialog.add_filter("*.png", "PNG Image")
	background_file_dialog.add_filter("*.jpg,*.jpeg", "JPEG Image")
	background_file_dialog.add_filter("*.webp", "WebP Image")
	background_file_dialog.add_filter("*.ogv", "Ogg Theora Video")
	background_file_dialog.add_filter("*.webm", "WebM Video")
	background_file_dialog.add_filter("*.mp4", "MP4 Video")
	background_file_dialog.file_selected.connect(_on_background_file_selected)
	add_child(background_file_dialog)

# 選択されたレイアウトファイルを検証して適用する。
func _on_layout_file_selected(path: String) -> void:
	apply_layout_file(path)

# 選択されたお題ファイルを検証して適用する。
func _on_odai_file_selected(path: String) -> void:
	apply_odai_file(path)

# 選択された背景画像を読み込んで適用する。
func _on_background_file_selected(path: String) -> void:
	apply_background_file(path)

# 背景画像を適用し、表示ラベルを更新する。
func apply_background_file(path: String) -> bool:
	if is_video_file_path(path):
		return apply_background_video_file(path)
	return apply_background_image_file(path)

# ファイル拡張子から動画かどうかを判定する。
func is_video_file_path(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	return ext == "ogv" or ext == "webm" or ext == "mp4" or ext == "mkv" or ext == "avi" or ext == "mov"

# 背景画像を適用する。
func apply_background_image_file(path: String) -> bool:
	var tex: Texture2D = null
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		tex = ImageTexture.create_from_image(img)
	else:
		# Fallback for resources under res:// that can be loaded as Texture2D.
		var loaded := load(path)
		if loaded is Texture2D:
			tex = loaded as Texture2D

	if tex == null:
		push_error("Background image load failed: " + path)
		return false
	current_background_path = path
	current_background_is_video = false
	var bg := ui_node("background_texture") as TextureRect
	if bg != null:
		bg.texture = tex
		bg.visible = true
	var video := ui_node("background_video") as VideoStreamPlayer
	if video != null:
		video.stop()
		video.stream = null
		video.visible = false
	apply_background_texture_settings()
	update_background_label()
	save_app_settings()
	return true

# 背景動画を適用する。
func apply_background_video_file(path: String) -> bool:
	var stream: VideoStream = null
	var loaded := ResourceLoader.load(path)
	if loaded is VideoStream:
		stream = loaded as VideoStream

	if stream == null and ClassDB.class_exists("VideoStreamTheora"):
		var theora_obj: Variant = ClassDB.instantiate("VideoStreamTheora")
		if theora_obj != null:
			theora_obj.set("file", path)
			if theora_obj is VideoStream:
				stream = theora_obj as VideoStream

	if stream == null:
		push_error("Background video load failed (supported may vary by platform): " + path)
		return false

	current_background_path = path
	current_background_is_video = true
	var video := ui_node("background_video") as VideoStreamPlayer
	if video != null:
		configure_background_video_player()
		video.stream = stream
		video.visible = true
		video.play()
	var bg := ui_node("background_texture") as TextureRect
	if bg != null:
		bg.visible = false
		apply_background_texture_settings()
	update_background_label()
	save_app_settings()
	return true

# アプリ設定を user://app_settings.json に保存する。
func save_app_settings() -> void:
	var data: Dictionary = {
		"layout_path": current_layout_path,
		"odai_path": current_odai_path,
		"ui_font_size": ui_font_size,
		"background_path": current_background_path,
		"background_is_video": current_background_is_video,
	}
	var file: FileAccess = FileAccess.open(APP_SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open app settings for write: " + APP_SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(data))
	file.close()

# 起動時にアプリ設定を読み込み、配列/お題/背景を復元する。
func load_app_settings() -> void:
	if not FileAccess.file_exists(APP_SETTINGS_PATH):
		return
	var file: FileAccess = FileAccess.open(APP_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open app settings for read: " + APP_SETTINGS_PATH)
		return
	var raw: String = file.get_as_text()
	file.close()

	var parsed_result: Variant = JSON.parse_string(raw)
	if not (parsed_result is Dictionary):
		return
	var data: Dictionary = parsed_result as Dictionary

	var saved_font_size := int(data.get("ui_font_size", ui_font_size))
	if saved_font_size >= 8:
		ui_font_size = saved_font_size
		if has_ui_node("font_size_spinbox"):
			(ui_node("font_size_spinbox") as SpinBox).value = ui_font_size
		apply_ui_font_size()
		refresh_ui()

	var saved_layout_path: String = String(data.get("layout_path", "")).strip_edges()
	if not saved_layout_path.is_empty() and FileAccess.file_exists(saved_layout_path):
		apply_layout_file(saved_layout_path)

	var saved_odai_path: String = String(data.get("odai_path", "")).strip_edges()
	if not saved_odai_path.is_empty() and FileAccess.file_exists(saved_odai_path):
		apply_odai_file(saved_odai_path)

	var bg_path: String = String(data.get("background_path", "")).strip_edges()
	if bg_path.is_empty():
		return

	# 起動時にファイルが消えていた場合は復元せず、ラベルだけ初期状態にする。
	if not FileAccess.file_exists(bg_path):
		current_background_path = ""
		current_background_is_video = false
		update_background_label()
		return

	if not apply_background_file(bg_path):
		current_background_path = ""
		current_background_is_video = false
		update_background_label()

# 背景表示ラベルを更新する。
func update_background_label() -> void:
	if not has_ui_node("background_label"):
		return
	var label := ui_node("background_label") as RichTextLabel
	if label == null:
		return
	label.clear()
	if current_background_path.is_empty():
		label.append_text("(背景なし)")
	else:
		var kind := "動画" if current_background_is_video else "画像"
		label.append_text("%s: %s" % [kind, current_background_path.get_file()])

# 背景画像を引き伸ばさずに表示する設定を適用する。
func apply_background_texture_settings() -> void:
	var bg := ui_node("background_texture") as TextureRect
	if bg == null:
		pass
	else:
		bg.stretch_mode = TextureRect.STRETCH_KEEP
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.z_index = -100

	var video := ui_node("background_video") as VideoStreamPlayer
	if video != null:
		video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		video.z_index = -99

# 背景動画プレイヤーの共通設定を行う。
func configure_background_video_player() -> void:
	var video := ui_node("background_video") as VideoStreamPlayer
	if video == null:
		return
	video.loop = true
	if not video.finished.is_connected(_on_background_video_finished):
		video.finished.connect(_on_background_video_finished)

# ループ未対応ストリーム向けのフォールバック再生。
func _on_background_video_finished() -> void:
	var video := ui_node("background_video") as VideoStreamPlayer
	if video == null:
		return
	if not current_background_is_video:
		return
	if not video.visible:
		return
	if video.stream == null:
		return
	video.play()

# レイアウトJSONを検証し、問題なければ入力テーブルを切り替える。
func apply_layout_file(path: String) -> bool:
	var rules := load_json_array(path)
	if rules.is_empty():
		push_error("Layout file is empty or invalid: " + path)
		return false
	if not validate_layout_rules(path, rules):
		push_error(last_layout_validation_error)
		return false

	current_layout_path = path
	table = build_table(rules)
	sentence_cache.clear()
	reset_prompts()
	update_layout_label()
	save_app_settings()
	return true

# お題ファイルを検証し、問題なければ反映する。
func apply_odai_file(path: String) -> bool:
	var checked := validate_and_load_odai_lines(path)
	if not bool(checked.get("ok", false)):
		push_error(last_odai_validation_error)
		return false

	current_odai_path = path
	odai_lines = checked.get("lines", [])
	sentence_cache.clear()
	reset_prompts()
	update_odai_label()
	save_app_settings()
	return true

# レイアウトJSONが state/input/output/next_state を持つ配列か検証する。
func validate_layout_rules(path: String, rules: Array) -> bool:
	last_layout_validation_error = ""
	var raw_text := load_raw(path)
	var lines := raw_text.replace("\r", "").split("\n", false)
	var search_start_line := 1

	for rule in rules:
		if not (rule is Dictionary):
			last_layout_validation_error = "Layout format error: rule is not Dictionary"
			return false
		if not rule.has("state") or not rule.has("input") or not rule.has("output") or not rule.has("next_state"):
			var line_missing := find_rule_line(lines, rule, search_start_line)
			last_layout_validation_error = "Layout format error at line %d: required keys are missing" % line_missing
			return false
		var state: Variant = rule["state"]
		var input_char: Variant = rule["input"]
		var output: Variant = rule["output"]
		var next_state: Variant = rule["next_state"]
		var line_no := find_rule_line(lines, rule, search_start_line)
		search_start_line = maxi(line_no, search_start_line)
		if not (state is String and input_char is String and output is String and next_state is String):
			last_layout_validation_error = "Layout format error at line %d: state/input/output/next_state must be String" % line_no
			return false
		if String(state).is_empty() or String(input_char).is_empty() or String(next_state).is_empty():
			last_layout_validation_error = "Layout format error at line %d: state/input/next_state must not be empty" % line_no
			return false
	return true

# レイアウト1ルールのおおよその行番号を検索する。
func find_rule_line(lines: Array[String], rule: Dictionary, start_line: int) -> int:
	var state := String(rule.get("state", ""))
	var input_char := String(rule.get("input", ""))
	var token_a := '"state": "%s"' % state
	var token_b := '"input": "%s"' % input_char
	for i in range(maxi(start_line - 1, 0), lines.size()):
		var line := lines[i]
		if line.find(token_a) != -1 and line.find(token_b) != -1:
			return i + 1
	return start_line

# 現在使用中のお題ファイル名を odai_label に表示する。
func update_odai_label() -> void:
	if not has_ui_node("odai_label"):
		return
	var file_name := current_odai_path.get_file()
	var label := ui_node("odai_label") as RichTextLabel
	label.clear()
	label.append_text(file_name)

# お題テキストを読み込み、形式検証と行番号付きエラー生成を行う。
func validate_and_load_odai_lines(path: String) -> Dictionary:
	last_odai_validation_error = ""
	var raw_text := load_raw(path)
	if raw_text.is_empty():
		last_odai_validation_error = "Odai format error: empty file (%s)" % path
		return {"ok": false, "lines": []}

	var lines := raw_text.replace("\r", "").split("\n", false)
	var result_lines: Array[String] = []
	for i in range(lines.size()):
		var line_no := i + 1
		var line := String(lines[i]).strip_edges()
		if line.is_empty():
			continue
		var err := validate_odai_line(line)
		if not err.is_empty():
			last_odai_validation_error = "Odai format error at line %d: %s" % [line_no, err]
			return {"ok": false, "lines": []}
		result_lines.append(line)

	if result_lines.is_empty():
		last_odai_validation_error = "Odai format error: no usable lines (%s)" % path
		return {"ok": false, "lines": []}

	return {"ok": true, "lines": result_lines}

# お題1行の構文を検証し、問題があれば説明文字列を返す。
func validate_odai_line(line: String) -> String:
	var i := 0
	while i < line.length():
		if line[i] == "[":
			var close_bracket := line.find("]", i + 1)
			if close_bracket == -1:
				return "']' が見つかりません"
			if close_bracket + 1 >= line.length() or line[close_bracket + 1] != "(":
				return "']' の直後は '(' である必要があります"
			var close_paren := line.find(")", close_bracket + 2)
			if close_paren == -1:
				return "')' が見つかりません"
			if close_bracket == i + 1:
				return "[] 内の表記が空です"
			if close_paren == close_bracket + 2:
				return "() 内のルビが空です"
			i = close_paren + 1
			continue

		if is_kanji_char(line[i]):
			return "ルビのない漢字 '%s' があります" % line[i]
		i += 1

	return ""

# 1文字が漢字かどうかを判定する。
func is_kanji_char(ch: String) -> bool:
	if ch.is_empty():
		return false
	var code := ch.unicode_at(0)
	if code >= 0x3400 and code <= 0x4DBF:
		return true
	if code >= 0x4E00 and code <= 0x9FFF:
		return true
	if code >= 0xF900 and code <= 0xFAFF:
		return true
	return false

# 現在使用中の配列ファイル名を layout_label に表示する。
func update_layout_label() -> void:
	if not has_ui_node("layout_label"):
		return
	var file_name := current_layout_path.get_file()
	var label := ui_node("layout_label") as RichTextLabel
	label.clear()
	label.append_text(file_name)

# スタートボタン押下で1分タイマーを開始し、プレイ状態を初期化する。
func _on_start_button_pressed() -> void:
	start_round()

# タイマーモード変更時にUI状態と待機時表示時間を更新する。
func _on_timer_mode_option_item_selected(_index: int) -> void:
	update_custom_time_visibility()
	if not timer_running and not countdown_running:
		time_left_sec = get_round_time_sec()
		update_timer_label()

# 自由設定秒数の変更時に待機時表示時間を更新する。
func _on_custom_time_spinbox_value_changed(_value: float) -> void:
	if not timer_running and not countdown_running:
		time_left_sec = get_round_time_sec()
		update_timer_label()

# カウントダウン秒数の変更時に待機表示を更新する。
func _on_countdown_spinbox_value_changed(_value: float) -> void:
	if not timer_running and not countdown_running:
		update_timer_label()

# フォントサイズ変更時にUIへ反映する。
func _on_font_size_spinbox_value_changed(value: float) -> void:
	ui_font_size = maxi(int(round(value)), 8)
	apply_ui_font_size()
	refresh_ui()

# タイマー選択UI（1分/1時間/自由設定）を初期化する。
func setup_timer_mode_option() -> void:
	if not has_ui_node("timer_mode_option"):
		return

	var option := ui_node("timer_mode_option") as OptionButton
	option.clear()
	option.add_item("1分", TIMER_MODE_1MIN)
	option.add_item("1時間", TIMER_MODE_1HOUR)
	option.add_item("自由設定", TIMER_MODE_CUSTOM)
	option.select(TIMER_MODE_1MIN)

	if has_ui_node("custom_time_spinbox"):
		var spin := ui_node("custom_time_spinbox") as SpinBox
		spin.min_value = 1
		spin.max_value = 86400
		spin.step = 1
		if spin.value < 1:
			spin.value = 60

# 開始前カウントダウン秒数入力UIを初期化する。
func setup_countdown_spinbox() -> void:
	if not has_ui_node("countdown_spinbox"):
		return
	var spin := ui_node("countdown_spinbox") as SpinBox
	spin.min_value = 0
	spin.max_value = 60
	spin.step = 1
	if spin.value < 0:
		spin.value = 0

# フォントサイズ入力UIを初期化する。
func setup_font_size_spinbox() -> void:
	if not has_ui_node("font_size_spinbox"):
		return
	var spin := ui_node("font_size_spinbox") as SpinBox
	ui_font_size = 25
	spin.min_value = 8
	spin.max_value = 500
	spin.step = 1
	# 起動時はシーン保存値に関わらず既定値(25)を適用する。
	spin.value = ui_font_size
	ui_font_size = int(spin.value)

# 主要UIのフォントサイズを現在設定で更新する。
func apply_ui_font_size() -> void:
	var rich_targets := ["timer_label", "target_text2", "target_text", "measure_label", "layout_label", "odai_label", "countdown_label", "font_size_label", "background_label"]
	for name in rich_targets:
		var n := ui_node(name)
		if n is RichTextLabel:
			(n as RichTextLabel).add_theme_font_size_override("normal_font_size", ui_font_size)

# 開始前カウントダウン秒数を返す。
func get_countdown_sec() -> float:
	if not has_ui_node("countdown_spinbox"):
		return 0.0
	var spin := ui_node("countdown_spinbox") as SpinBox
	return maxf(float(spin.value), 0.0)

# 現在選択中モードに応じて計測秒数を返す。
func get_round_time_sec() -> float:
	if not has_ui_node("timer_mode_option"):
		return DEFAULT_ROUND_TIME_SEC

	var option := ui_node("timer_mode_option") as OptionButton
	var mode_id: int = option.get_selected_id()
	if mode_id == TIMER_MODE_1HOUR:
		return 3600.0
	if mode_id == TIMER_MODE_CUSTOM:
		if has_ui_node("custom_time_spinbox"):
			var spin := ui_node("custom_time_spinbox") as SpinBox
			return maxf(float(spin.value), 1.0)
		return DEFAULT_ROUND_TIME_SEC
	return 60.0

# 自由設定モードのときのみ秒数入力UIを表示する。
func update_custom_time_visibility() -> void:
	if not has_ui_node("custom_time_spinbox"):
		return

	var visible := false
	if has_ui_node("timer_mode_option"):
		var option := ui_node("timer_mode_option") as OptionButton
		visible = option.get_selected_id() == TIMER_MODE_CUSTOM

	(ui_node("custom_time_spinbox") as SpinBox).visible = visible

# 1ラウンドを初期化してタイマーを開始する。
func start_round() -> void:
	hide_result_overlay()

	if kana_stream.is_empty():
		ensure_lookahead()

	countdown_left_sec = get_countdown_sec()
	if countdown_left_sec > 0.0:
		countdown_running = true
		timer_running = false
	else:
		begin_measurement()

	if has_ui_node("start_button"):
		(ui_node("start_button") as Button).disabled = true
	update_timer_label()
	update_measure_label()
	update_timer_locked_buttons()
	update_start_button_shortcut_label()
	refresh_ui()

# 本計測を開始し、計測残り時間を初期化する。
func begin_measurement() -> void:
	countdown_running = false
	timer_running = true
	time_left_sec = get_round_time_sec()
	round_start_msec = Time.get_ticks_msec()
	input_events.clear()

# 毎フレームタイマーを更新し、0秒でラウンドを終了する。
func update_timer(delta: float) -> void:
	if countdown_running:
		countdown_left_sec = maxf(countdown_left_sec - delta, 0.0)
		update_timer_label()
		update_measure_label()
		if countdown_left_sec <= 0.0:
			begin_measurement()
			update_timer_label()
			update_measure_label()
			update_timer_locked_buttons()
		return

	if not timer_running:
		return

	time_left_sec = maxf(time_left_sec - delta, 0.0)
	update_timer_label()
	if time_left_sec <= 0.0:
		finish_round(true)

# タイマー終了時の入力停止とUI状態復帰を行う。
func finish_round(time_up: bool, reset_after_finish: bool = true) -> void:
	var chars := typed_target_chars
	var misses := miss_count
	var score := chars - misses
	var measured_seconds := get_measured_seconds()

	countdown_running = false
	countdown_left_sec = 0.0
	timer_running = false
	if time_up:
		time_left_sec = 0.0
	if has_ui_node("start_button"):
		(ui_node("start_button") as Button).disabled = false
	update_timer_label()
	update_measure_label()
	update_timer_locked_buttons()
	update_start_button_shortcut_label()
	if time_up:
		save_record(chars, misses, score, measured_seconds)
		show_result_overlay(chars, misses, score)
	if reset_after_finish:
		reset_state()
		ensure_lookahead()
		refresh_ui()

# 計測結果を records/records.jsonl に1行JSONとして追記保存する。
func save_record(chars: int, misses: int, score: int, measured_seconds: float) -> void:
	if not ensure_records_dir():
		push_error("Failed to prepare records directory: " + RECORDS_DIR)
		return

	var dt := Time.get_datetime_dict_from_system()
	var created_at := "%04d-%02d-%02d %02d:%02d:%02d" % [
		int(dt.get("year", 0)),
		int(dt.get("month", 0)),
		int(dt.get("day", 0)),
		int(dt.get("hour", 0)),
		int(dt.get("minute", 0)),
		int(dt.get("second", 0)),
	]
	var record_id := "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var record := {
		"record_id": record_id,
		"created_at": created_at,
		"typed_chars": chars,
		"miss_count": misses,
		"score": score,
		"measured_seconds": measured_seconds,
		"odai_path": current_odai_path,
		"layout_path": current_layout_path,
		"round_seconds": int(get_round_time_sec()),
		"countdown_seconds": int(get_countdown_sec()),
		"input_events": input_events.duplicate(true),
		"odai_snapshot": {
			"unique_lines": used_odai_unique_lines.duplicate(),
			"line_order": used_odai_line_order.duplicate(),
		},
	}

	var file: FileAccess = null
	if FileAccess.file_exists(RECORDS_FILE_PATH):
		file = FileAccess.open(RECORDS_FILE_PATH, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(RECORDS_FILE_PATH, FileAccess.WRITE)

	if file == null:
		push_error("Failed to open record file: " + RECORDS_FILE_PATH)
		return

	file.store_line(JSON.stringify(record))
	file.close()

# その回の実測秒数を返す（入力イベントがあれば優先して利用）。
func get_measured_seconds() -> float:
	if not input_events.is_empty() and input_events[input_events.size() - 1] is Dictionary:
		var last_event := input_events[input_events.size() - 1] as Dictionary
		var t_ms := float(last_event.get("t_ms", 0.0))
		if t_ms > 0.0:
			return t_ms / 1000.0

	if round_start_msec > 0:
		var now_msec := Time.get_ticks_msec()
		var elapsed_msec := maxi(now_msec - round_start_msec, 0)
		return float(elapsed_msec) / 1000.0

	return 0.0

# 記録保存ディレクトリを作成する。
func ensure_records_dir() -> bool:
	var err := DirAccess.make_dir_recursive_absolute(RECORDS_DIR)
	return err == OK or err == ERR_ALREADY_EXISTS

# 計測中は各種設定・遷移系UIを非表示かつ無効化する。
func update_timer_locked_buttons() -> void:
	var locked := timer_running or countdown_running
	
	if has_ui_node("exit_button"):
		var btn_exit := ui_node("exit_button") as Control
		btn_exit.visible = not locked
		if btn_exit is BaseButton:
			(btn_exit as BaseButton).disabled = locked

	if has_ui_node("change_layout"):
		var btn_layout := ui_node("change_layout") as Control
		btn_layout.visible = not locked
		if btn_layout is BaseButton:
			(btn_layout as BaseButton).disabled = locked
	
	if has_ui_node("change_odai"):
		var btn_odai := ui_node("change_odai") as Control
		btn_odai.visible = not locked
		if btn_odai is BaseButton:
			(btn_odai as BaseButton).disabled = locked
	
	if has_ui_node("records_button"):
		var btn_records := ui_node("records_button") as Control
		btn_records.visible = not locked
		if btn_records is BaseButton:
			(btn_records as BaseButton).disabled = locked

	if has_ui_node("timer_mode_option"):
		var timer_mode := ui_node("timer_mode_option") as Control
		timer_mode.visible = not locked
		if timer_mode is BaseButton:
			(timer_mode as BaseButton).disabled = locked

	if has_ui_node("custom_time_spinbox"):
		var custom_time := ui_node("custom_time_spinbox") as Control
		custom_time.visible = not locked
		if custom_time is BaseButton:
			(custom_time as BaseButton).disabled = locked

	if has_ui_node("countdown_spinbox"):
		var countdown_time := ui_node("countdown_spinbox") as Control
		countdown_time.visible = not locked
		if countdown_time is BaseButton:
			(countdown_time as BaseButton).disabled = locked

	if has_ui_node("countdown_label"):
		(ui_node("countdown_label") as Control).visible = not locked

	if has_ui_node("font_size_spinbox"):
		var font_spin := ui_node("font_size_spinbox") as Control
		font_spin.visible = not locked
		if font_spin is BaseButton:
			(font_spin as BaseButton).disabled = locked

	if has_ui_node("font_size_label"):
		(ui_node("font_size_label") as Control).visible = not locked

	if has_ui_node("change_background"):
		var bg_btn := ui_node("change_background") as Control
		bg_btn.visible = not locked
		if bg_btn is BaseButton:
			(bg_btn as BaseButton).disabled = locked

	if has_ui_node("background_label"):
		(ui_node("background_label") as Control).visible = not locked

	if has_ui_node("layout_label"):
		(ui_node("layout_label") as Control).visible = not locked

	if has_ui_node("odai_label"):
		(ui_node("odai_label") as Control).visible = not locked

	if not locked:
		update_custom_time_visibility()

	update_start_button_shortcut_label()

# timer_label に残り時間を mm:ss 形式で表示する。
func update_timer_label() -> void:
	if not has_ui_node("timer_label"):
		return

	var total_sec: int
	if countdown_running:
		total_sec = int(ceil(countdown_left_sec))
	else:
		total_sec = int(ceil(time_left_sec))
	var min_part: int = total_sec / 60
	var sec_part: int = total_sec % 60
	var text := "%02d:%02d" % [min_part, sec_part]
	var label := ui_node("timer_label") as RichTextLabel
	label.clear()
	label.append_text(text)

# 計測状態ラベルを timer_running に合わせて更新する。
func update_measure_label() -> void:
	if not has_ui_node("measure_label"):
		return

	var label := ui_node("measure_label") as RichTextLabel
	label.clear()
	if countdown_running:
		label.append_text("開始カウントダウン中")
	elif timer_running:
		label.append_text("計測中(Escで停止)")
	else:
		label.append_text("計測停止中(Spaceで開始)")

# target_text 系で実際に数える文字数（区切り記号を除外）を範囲で返す。
func count_target_chars_in_range(start_idx: int, end_idx: int) -> int:
	if kanji_stream.is_empty():
		return 0
	var s := clampi(start_idx, 0, kanji_stream.length())
	var e := clampi(end_idx, 0, kanji_stream.length())
	if e <= s:
		return 0

	var count := 0
	for i in range(s, e):
		if kanji_stream[i] != "␣":
			count += 1
	return count

# 計測結果を表示するオーバーレイUIを動的生成する。
func setup_result_overlay() -> void:
	if not has_node("main_ui"):
		return
	if result_overlay != null:
		return

	result_overlay = Control.new()
	result_overlay.name = "result_overlay"
	result_overlay.anchor_left = 0.0
	result_overlay.anchor_top = 0.0
	result_overlay.anchor_right = 1.0
	result_overlay.anchor_bottom = 1.0
	result_overlay.offset_left = 0.0
	result_overlay.offset_top = 0.0
	result_overlay.offset_right = 0.0
	result_overlay.offset_bottom = 0.0
	result_overlay.visible = false
	add_child(result_overlay)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	backdrop.anchor_left = 0.0
	backdrop.anchor_top = 0.0
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	result_overlay.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -180.0
	panel.offset_top = -120.0
	panel.offset_right = 180.0
	panel.offset_bottom = 120.0
	result_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "計測結果"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var chars_label := Label.new()
	chars_label.text = "入力文字数:"
	vbox.add_child(chars_label)
	result_value_chars_label = Label.new()
	result_value_chars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(result_value_chars_label)

	var miss_label := Label.new()
	miss_label.text = "ミス数:"
	vbox.add_child(miss_label)
	result_value_miss_label = Label.new()
	result_value_miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(result_value_miss_label)

	var score_label := Label.new()
	score_label.text = "最終スコア:"
	vbox.add_child(score_label)
	result_value_score_label = Label.new()
	result_value_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(result_value_score_label)

	var close_button := Button.new()
	close_button.text = "閉じる"
	close_button.pressed.connect(_on_result_close_button_pressed)
	vbox.add_child(close_button)

# 結果オーバーレイにスコア情報を反映して表示する。
func show_result_overlay(chars: int, misses: int, score: int) -> void:
	if result_overlay == null:
		setup_result_overlay()
	if result_overlay == null:
		return
	if result_value_chars_label == null or result_value_miss_label == null or result_value_score_label == null:
		return

	result_value_chars_label.text = str(chars)
	result_value_miss_label.text = str(misses)
	result_value_score_label.text = str(score)
	result_overlay.visible = true
	update_start_button_shortcut_label()

# 結果オーバーレイを非表示にする。
func hide_result_overlay() -> void:
	if result_overlay != null:
		result_overlay.visible = false
	update_start_button_shortcut_label()

# 結果オーバーレイの閉じるボタン押下処理。
func _on_result_close_button_pressed() -> void:
	hide_result_overlay()

# お題を読み込み、内部状態を初期化して初期表示を行う。
func init_stream() -> void:
	odai_lines = load_odai_lines(current_odai_path)
	if odai_lines.is_empty():
		push_error("No Japanese odai lines loaded")
	
	reset_state()
	ensure_lookahead()
	refresh_ui()

# ゲーム進行に関する可変状態を初期値に戻す。
func reset_state() -> void:
	kana_stream = ""
	kanji_stream = ""
	kana_to_kanji = [0]
	chunks.clear()
	stream_cursor = 0
	current_state = "default"
	typed_history = ""
	key_timestamps.clear()
	miss_count = 0
	typed_target_chars = 0
	round_start_msec = 0
	input_events.clear()
	used_odai_unique_lines.clear()
	used_odai_line_order.clear()
	miss_timer = 0.0

# 先読み不足がなくなるまでお題を追加する。
func ensure_lookahead() -> void:
	while kana_stream.length() - stream_cursor < LOOKAHEAD_KANA:
		var data := pick_typable_sentence_data()
		if data.is_empty():
			break
		append_sentence_data(data)

# 入力可能な次のお題をランダムに選んで返す。
func pick_typable_sentence_data() -> Dictionary:
	if odai_lines.is_empty():
		return {}
	
	var max_try := mini(odai_lines.size() * 2, 300)
	for _i in range(max_try):
		var line: String = odai_lines.pick_random()
		var data := get_or_parse_sentence_data(line)
		if bool(data.get("typable", false)):
			return data
	
	push_error("No typable sentence found in odai file")
	return {}

# お題1行をキャッシュ利用で解析し、入力可能フラグ付きで返す。
func get_or_parse_sentence_data(line: String) -> Dictionary:
	if sentence_cache.has(line):
		var cached: Dictionary = sentence_cache[line]
		cached["source_line"] = line
		return cached
	
	var data := make_sentence_data(line)
	data["typable"] = can_type_kana(String(data.get("kana_text", "")))
	data["source_line"] = line
	sentence_cache[line] = data
	return data

# ルビ付き文字列を、表示文字列・かな文字列・対応マップへ分解する。
func make_sentence_data(ruby_text: String) -> Dictionary:
	var kanji_text := ""
	var kana_text := ""
	var map: Array[int] = []
	
	var i := 0
	while i < ruby_text.length():
		if ruby_text[i] == "[":
			var close_bracket := ruby_text.find("]", i + 1)
			if close_bracket != -1 and close_bracket + 1 < ruby_text.length() and ruby_text[close_bracket + 1] == "(":
				var close_paren := ruby_text.find(")", close_bracket + 2)
				if close_paren != -1:
					var base := ruby_text.substr(i + 1, close_bracket - i - 1)
					var ruby := ruby_text.substr(close_bracket + 2, close_paren - close_bracket - 2)
					
					kanji_text += base
					var ruby_hira := hiragana_katakana_to_hiragana(ruby)
					kana_text += ruby_hira
					for _j in range(ruby_hira.length()):
						map.append(kanji_text.length())
					i = close_paren + 1
					continue
		
		var ch := ruby_text[i]
		kanji_text += ch
		var hira := hiragana_katakana_to_hiragana(ch)
		kana_text += hira
		map.append(kanji_text.length())
		i += 1
	
	return {
		"kanji_text": kanji_text,
		"kana_text": kana_text,
		"map": map,
	}

# 解析済みお題をストリームへ連結し、文間区切りと対応マップを更新する。
func append_sentence_data(data: Dictionary) -> void:
	var kana_text: String = data.get("kana_text", "")
	var kanji_text: String = data.get("kanji_text", "")
	var rel_map: Array[int] = data.get("map", [])
	var source_line: String = data.get("source_line", "")
	
	if kana_text.is_empty() or kanji_text.is_empty():
		return

	if not source_line.is_empty():
		var idx := used_odai_unique_lines.find(source_line)
		if idx == -1:
			used_odai_unique_lines.append(source_line)
			idx = used_odai_unique_lines.size() - 1
		used_odai_line_order.append(idx)

	# Separator between prompts: type a real space, display it as "␣".
	if not chunks.is_empty():
		kanji_stream += "␣"
		kana_stream += " "
		kana_to_kanji.append(kanji_stream.length())
	
	var kana_start := kana_stream.length()
	var kanji_start := kanji_stream.length()
	
	kana_stream += kana_text
	kanji_stream += kanji_text
	
	for i in range(rel_map.size()):
		kana_to_kanji.append(kanji_start + int(rel_map[i]))
	
	chunks.append({
		"kana_start": kana_start,
		"kana_end": kana_stream.length(),
		"kanji_start": kanji_start,
		"kanji_end": kanji_stream.length(),
	})

# 1文字入力を状態機械で正誤判定し、遷移可能なら進行させる。
func check_input(input_char: String) -> void:
	check_input_candidates([input_char])

# 複数の入力候補を順に評価し、成立した候補で進行させる。
func check_input_candidates(input_candidates: Array[String]) -> void:
	if table.is_empty():
		return
	
	ensure_lookahead()
	if stream_cursor >= kana_stream.length():
		return
	if input_candidates.is_empty():
		return

	var expected_kana := ""
	if stream_cursor < kana_stream.length():
		expected_kana = kana_stream[stream_cursor]
	var expected_target := ""
	var target_idx := get_caret_index_in_kanji(stream_cursor)
	if target_idx >= 0 and target_idx < kanji_stream.length():
		expected_target = kanji_stream[target_idx]
	var snap_target3 := get_hbox_visible_text(ui_node("target_text3"))
	var snap_hiragana := get_hbox_visible_text(ui_node("hiragana_box"))
	var snap_history := get_hbox_visible_text(ui_node("history_box"))

	var transitions: Dictionary = table.get(current_state, {})
	var miss_key := input_candidates[0]
	var miss_reason := "invalid_transition"

	for input_char in input_candidates:
		if not transitions.has(input_char):
			continue

		var transition: Dictionary = transitions[input_char]
		var output := String(transition.get("output", ""))
		if not output_matches_at(output, stream_cursor):
			if miss_reason == "invalid_transition":
				miss_reason = "output_mismatch"
				miss_key = input_char
			continue

		var next_state := String(transition.get("next", "default"))
		var next_pos := stream_cursor + output.length()
		# Empty-output transitions can be traps (e.g. default->k when next kana is not k*).
		# Treat those as miss so the game never enters an unwinnable state.
		if not can_type_text_from(kana_stream, next_state, next_pos):
			miss_reason = "dead_end"
			miss_key = input_char
			continue

		log_input_event(input_char, true, expected_kana, expected_target, "ok", snap_target3, snap_hiragana, snap_history)
		on_correct(input_char, transition, output)
		return

	log_input_event(miss_key, false, expected_kana, expected_target, miss_reason, snap_target3, snap_hiragana, snap_history)
	on_miss(miss_key)

# 計測中の入力イベントを時刻付きで記録する。
func log_input_event(input_char: String, ok: bool, expected_kana: String, expected_target: String, reason: String, snap_target3: String, snap_hiragana: String, snap_history: String) -> void:
	if not timer_running:
		return
	if round_start_msec <= 0:
		return
	var now_msec := Time.get_ticks_msec()
	input_events.append({
		"t_ms": now_msec - round_start_msec,
		"key": input_char,
		"ok": ok,
		"expected_kana": expected_kana,
		"expected_target": expected_target,
		"reason": reason,
		"snap_target3": snap_target3,
		"snap_hiragana": snap_hiragana,
		"snap_history": snap_history,
	})

# HBox内のラベル文字列を連結して現在の見た目テキストを返す。
func get_hbox_visible_text(node: Node) -> String:
	if node == null:
		return ""
	if not (node is HBoxContainer):
		return ""
	var box := node as HBoxContainer
	var text := ""
	for child in box.get_children():
		if child is Label:
			text += (child as Label).text
	return text

# 正解入力時の履歴・状態・進捗更新を行う。
func on_correct(input_char: String, transition: Dictionary, output: String) -> void:
	typed_history += input_char
	current_state = String(transition.get("next", "default"))
	
	if not output.is_empty():
		var prev_kanji_caret := get_caret_index_in_kanji(stream_cursor)
		stream_cursor += output.length()
		var next_kanji_caret := get_caret_index_in_kanji(stream_cursor)
		typed_target_chars += count_target_chars_in_range(prev_kanji_caret, next_kanji_caret)
		key_timestamps.append(Time.get_ticks_msec() / 1000.0)
	
	ensure_lookahead()
	miss_timer = 0.0
	refresh_ui()

# ミス入力時のカウントと赤表示タイマー開始を行う。
func on_miss(_input_char: String) -> void:
	miss_count += 1
	miss_timer = MISS_FLASH_TIME
	refresh_ui()

# 現在カーソル位置で遷移出力文字列が一致するか判定する。
func output_matches_at(output: String, cursor: int) -> bool:
	if output.is_empty():
		return true
	if cursor + output.length() > kana_stream.length():
		return false
	return kana_stream.substr(cursor, output.length()) == output

# 主要表示コンポーネントをまとめて再描画する。
func refresh_ui() -> void:
	update_target_label()
	update_next_target_label()
	update_target_flow_box()
	update_hiragana_box()
	update_history_box()
	align_input_boxes_to_target_caret()

# 現在お題のみを target_text に進捗ハイライト付きで表示する。
func update_target_label() -> void:
	var label := ui_node("target_text") as RichTextLabel
	if label == null:
		return
	label.clear()
	
	if kanji_stream.is_empty():
		return
	
	var current_chunk_index := get_current_chunk_index()
	if current_chunk_index < 0 or current_chunk_index >= chunks.size():
		return
	
	var chunk := chunks[current_chunk_index]
	var start := int(chunk["kanji_start"])
	var end := int(chunk["kanji_end"])
	var caret := get_caret_index_in_kanji(stream_cursor)
	var miss_active := miss_timer > 0.0
	
	for i in range(start, end):
		var ch := kanji_stream[i]
		if i < caret:
			label.push_color(Color.GRAY)
		elif i == caret and miss_active:
			label.push_color(Color.RED)
		elif i == caret:
			label.push_color(Color.CYAN)
		else:
			label.push_color(Color.WHITE)
		label.add_text(ch)
		label.pop()

# 次のお題を target_text2 に常時表示する。
func update_next_target_label() -> void:
	if not has_ui_node("target_text2"):
		return

	ensure_next_chunk_for_display()
	
	var label := ui_node("target_text2") as RichTextLabel
	label.clear()
	
	if chunks.is_empty() or kanji_stream.is_empty():
		return
	
	var current_chunk_index := get_current_chunk_index()
	var next_chunk_index := current_chunk_index + 1
	if next_chunk_index < 0 or next_chunk_index >= chunks.size():
		return
	
	var next_chunk := chunks[next_chunk_index]
	var start := int(next_chunk["kanji_start"])
	var end := int(next_chunk["kanji_end"])
	for i in range(start, end):
		label.push_color(Color.WHITE)
		label.add_text(kanji_stream[i])
		label.pop()

# 次お題表示用に、現在位置の次チャンクまで先読みを補充する。
func ensure_next_chunk_for_display() -> void:
	if odai_lines.is_empty():
		return

	var current_chunk_index := get_current_chunk_index()
	var required_count := 2
	if current_chunk_index >= 0:
		required_count = current_chunk_index + 2

	while chunks.size() < required_count:
		var data := pick_typable_sentence_data()
		if data.is_empty():
			break
		append_sentence_data(data)

# target_text3 に流れる漢字表示を描画する。
func update_target_flow_box() -> void:
	if not has_ui_node("target_text3"):
		return
	
	var box := ui_node("target_text3") as HBoxContainer
	for c in box.get_children():
		c.queue_free()
	
	if kanji_stream.is_empty():
		target_flow_caret_child_index = 0
		return
	
	var caret := get_caret_index_in_kanji(stream_cursor)
	var start := maxi(caret - max_items, 0)
	var end := mini(caret + LOOKAHEAD_KANA, kanji_stream.length())
	var miss_active := miss_timer > 0.0
	if end <= start:
		target_flow_caret_child_index = 0
		return
	target_flow_caret_child_index = clampi(caret - start, 0, end - start - 1)
	
	for i in range(start, end):
		var label := Label.new()
		label.text = kanji_stream[i]
		label.add_theme_font_size_override("font_size", ui_font_size)
		
		if i < caret:
			label.modulate = Color.GRAY
		elif i == caret and miss_active:
			label.modulate = Color.RED
		elif i == caret:
			label.modulate = Color.CYAN
		else:
			label.modulate = Color.WHITE
		
		box.add_child(label)

# かなカーソル位置から現在お題チャンクのインデックスを返す。
func get_current_chunk_index() -> int:
	if chunks.is_empty():
		return -1
	
	for i in range(chunks.size()):
		if stream_cursor < int(chunks[i]["kana_end"]):
			return i
	
	return chunks.size() - 1

# かな進捗表示ボックスを更新する（空白は記号表示）。
func update_hiragana_box() -> void:
	var box := ui_node("hiragana_box") as HBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	
	if kana_stream.is_empty():
		hiragana_caret_child_index = 0
		return
	
	var start := maxi(stream_cursor - max_items, 0)
	var end := mini(stream_cursor + LOOKAHEAD_KANA, kana_stream.length())
	var miss_active := miss_timer > 0.0
	if end <= start:
		hiragana_caret_child_index = 0
		return
	hiragana_caret_child_index = clampi(stream_cursor - start, 0, end - start - 1)
	
	for i in range(start, end):
		var ch := kana_stream[i]
		var label := Label.new()
		label.text = "␣" if ch == " " else ch
		label.add_theme_font_size_override("font_size", ui_font_size)
		
		if i < stream_cursor:
			label.modulate = Color.GRAY
		elif i == stream_cursor and miss_active:
			label.modulate = Color.RED
		elif i == stream_cursor:
			label.modulate = Color.CYAN
		else:
			label.modulate = Color.WHITE
		
		box.add_child(label)

# 入力履歴と先読みプロンプトの表示ボックスを更新する。
func update_history_box() -> void:
	var box := ui_node("history_box") as HBoxContainer
	if box == null:
		return
	for c in box.get_children():
		c.queue_free()
	
	var history_start := maxi(typed_history.length() - max_items, 0)
	var past := typed_history.substr(history_start, typed_history.length() - history_start)
	var prompt := build_next_prompt(LOOKAHEAD_KANA)
	
	var combined := past + prompt
	var miss_active := miss_timer > 0.0
	if combined.is_empty():
		history_caret_child_index = 0
		return
	history_caret_child_index = clampi(past.length(), 0, combined.length() - 1)
	
	for i in range(combined.length()):
		var label := Label.new()
		var ch := combined[i]
		label.text = "␣" if ch == " " else ch
		label.add_theme_font_size_override("font_size", ui_font_size)
		
		if i < past.length():
			label.modulate = Color.GRAY
		elif i == past.length() and miss_active:
			label.modulate = Color.RED
		elif i == past.length():
			label.modulate = Color.CYAN
		else:
			label.modulate = Color.WHITE
		
		box.add_child(label)

# HBox内の指定キャレット位置までの横幅を返す。
func get_caret_x_in_hbox(box: HBoxContainer, caret_index: int) -> float:
	if box == null:
		return 0.0
	var child_count := box.get_child_count()
	if child_count <= 0:
		return 0.0

	var idx := clampi(caret_index, 0, child_count - 1)
	var x := 0.0
	var sep := float(box.get_theme_constant("separation"))
	for i in range(idx):
		var child := box.get_child(i)
		if child is Control:
			x += (child as Control).get_combined_minimum_size().x
			x += sep
	return x

# target_text3のキャレットXに合わせて、入力系ボックスの横位置を調整する。
func align_input_boxes_to_target_caret() -> void:
	if not has_ui_node("target_text3"):
		return
	if not has_ui_node("hiragana_box"):
		return
	if not has_ui_node("history_box"):
		return

	var target_box := ui_node("target_text3") as HBoxContainer
	var hira_box := ui_node("hiragana_box") as HBoxContainer
	var history_box := ui_node("history_box") as HBoxContainer
	if target_box.get_child_count() <= 0:
		return
	if hira_box.get_child_count() <= 0:
		return
	if history_box.get_child_count() <= 0:
		return

	var target_caret_x := get_caret_x_in_hbox(target_box, target_flow_caret_child_index)
	var target_global_x := target_box.position.x + target_caret_x

	var hira_caret_x := get_caret_x_in_hbox(hira_box, hiragana_caret_child_index)
	hira_target_x = target_global_x - hira_caret_x

	var history_caret_x := get_caret_x_in_hbox(history_box, history_caret_child_index)
	history_target_x = target_global_x - history_caret_x

	# 初回だけは現在位置を目標に合わせ、以後は補間で追従する。
	if not smooth_follow_initialized:
		hira_box.position.x = hira_target_x
		history_box.position.x = history_target_x
		smooth_follow_initialized = true

# 入力ボックスの横位置を目標値へ滑らかに補間する。
func update_input_boxes_smooth(delta: float) -> void:
	if not smooth_follow_initialized:
		return
	if not has_ui_node("hiragana_box"):
		return
	if not has_ui_node("history_box"):
		return

	var hira_box := ui_node("hiragana_box") as HBoxContainer
	var history_box := ui_node("history_box") as HBoxContainer
	if hira_box.get_child_count() <= 0:
		return
	if history_box.get_child_count() <= 0:
		return

	var t := clampf(delta * INPUT_BOX_FOLLOW_SPEED, 0.0, 1.0)
	hira_box.position.x = lerpf(hira_box.position.x, hira_target_x, t)
	history_box.position.x = lerpf(history_box.position.x, history_target_x, t)

# 現在状態から先読み用の推奨入力列を生成する。
func build_next_prompt(max_len: int) -> String:
	if stream_cursor >= kana_stream.length():
		return ""
	
	var target_end := mini(kana_stream.length(), stream_cursor + LOOKAHEAD_KANA)
	var prompt := find_shortest_prompt(current_state, stream_cursor, target_end)
	if prompt.length() > max_len:
		return prompt.substr(0, max_len)
	return prompt

# 幅優先探索で、目標位置までの最短入力シーケンスを求める。
func find_shortest_prompt(start_state: String, start_pos: int, target_pos: int) -> String:
	var start_key := node_key(start_state, start_pos)
	var queue: Array[Dictionary] = [ {"state": start_state, "pos": start_pos}]
	var visited: Dictionary = {start_key: true}
	var parent: Dictionary = {}
	var head := 0
	
	var best_key := start_key
	var best_pos := start_pos
	
	while head < queue.size():
		var node := queue[head]
		head += 1
		
		var state := String(node["state"])
		var pos := int(node["pos"])
		if pos > best_pos:
			best_pos = pos
			best_key = node_key(state, pos)
		
		if pos >= target_pos:
			best_key = node_key(state, pos)
			break
		
		var transitions: Dictionary = table.get(state, {})
		for input_key in transitions.keys():
			var transition: Dictionary = transitions[input_key]
			var output := String(transition.get("output", ""))
			if not output_matches_at(output, pos):
				continue
			
			var next_pos := pos + output.length()
			var next_state := String(transition.get("next", "default"))
			var next_key := node_key(next_state, next_pos)
			if visited.has(next_key):
				continue
			
			visited[next_key] = true
			parent[next_key] = {
				"prev": node_key(state, pos),
				"input": String(input_key),
			}
			queue.append({"state": next_state, "pos": next_pos})
	
	if best_key == start_key:
		var keys := get_next_valid_keys(start_state, start_pos)
		if keys.is_empty():
			return ""
		return keys[0]
	
	var rev_steps: Array[String] = []
	var walk_key := best_key
	while walk_key != start_key and parent.has(walk_key):
		var step: Dictionary = parent[walk_key]
		rev_steps.append(String(step["input"]))
		walk_key = String(step["prev"])
	
	rev_steps.reverse()
	var result := ""
	for s in rev_steps:
		result += s
	return result

# 現在状態・位置で有効かつ完走可能な次キー候補を返す。
func get_next_valid_keys(state: String, pos: int) -> Array[String]:
	var keys: Array[String] = []
	var transitions: Dictionary = table.get(state, {})
	for input_key in transitions.keys():
		var transition: Dictionary = transitions[input_key]
		var output := String(transition.get("output", ""))
		if not output_matches_at(output, pos):
			continue
		var next_state := String(transition.get("next", "default"))
		var next_pos := pos + output.length()
		if can_type_text_from(kana_stream, next_state, next_pos):
			keys.append(String(input_key))
	keys.sort()
	return keys

# かな全文が既定レイアウトで入力可能かを判定する。
func can_type_kana(text: String) -> bool:
	if text.is_empty():
		return false
	return can_type_text_from(text, "default", 0)

# 任意の開始状態・開始位置から末尾まで到達可能かを判定する。
func can_type_text_from(text: String, start_state: String, start_pos: int) -> bool:
	if start_pos < 0 or start_pos > text.length():
		return false
	
	var start_key := node_key(start_state, start_pos)
	var queue: Array[Dictionary] = [ {"state": start_state, "pos": start_pos}]
	var visited: Dictionary = {start_key: true}
	var head := 0
	
	while head < queue.size():
		var node := queue[head]
		head += 1
		
		var state := String(node["state"])
		var pos := int(node["pos"])
		if pos >= text.length():
			return true
		
		var transitions: Dictionary = table.get(state, {})
		for input_key in transitions.keys():
			var transition: Dictionary = transitions[input_key]
			var output := String(transition.get("output", ""))
			if output.is_empty():
				var next_state := String(transition.get("next", "default"))
				var next_key := node_key(next_state, pos)
				if not visited.has(next_key):
					visited[next_key] = true
					queue.append({"state": next_state, "pos": pos})
				continue
			
			if pos + output.length() > text.length():
				continue
			if text.substr(pos, output.length()) != output:
				continue
			
			var n_state := String(transition.get("next", "default"))
			var n_pos := pos + output.length()
			var n_key := node_key(n_state, n_pos)
			if visited.has(n_key):
				continue
			
			visited[n_key] = true
			queue.append({"state": n_state, "pos": n_pos})
	
	return false

# かなカーソル位置に対応する漢字表示上のキャレット位置を返す。
func get_caret_index_in_kanji(kana_index: int) -> int:
	if kana_to_kanji.is_empty():
		return 0
	if kana_index < 0:
		return 0
	if kana_index >= kana_to_kanji.size():
		return kanji_stream.length()
	return kana_to_kanji[kana_index]

# 状態と位置を探索用キー文字列に変換する。
func node_key(state: String, pos: int) -> String:
	return "%s|%d" % [state, pos]

# ファイルをテキストとして読み込んで返す。
func load_raw(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return ""
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file: " + path)
		return ""
	
	var content := file.get_as_text()
	file.close()
	return content

# お題ファイルを行単位で読み込み、空行除去して返す。
func load_odai_lines(path: String) -> Array[String]:
	var raw_text := load_raw(path)
	if raw_text.is_empty():
		return []
	
	var lines := raw_text.replace("\r", "").split("\n", false)
	var result: Array[String] = []
	for line in lines:
		var trimmed := String(line).strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)
	
	return result

# JSON配列ファイルを読み込み、配列として返す。
func load_json_array(path: String) -> Array:
	var json_text := load_raw(path)
	if json_text.is_empty():
		return []
	
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("JSON Parse Error: %s in %s at line %s" % [json.get_error_message(), path, json.get_error_line()])
		return []
	
	if not (json.data is Array):
		push_error("JSON Error: Root element is NOT an Array in " + path)
		return []
	
	return json.data as Array

# 入力定義JSONを状態遷移テーブルへ変換し、スペース遷移を補完する。
func build_table(rules: Array) -> Dictionary:
	var result: Dictionary = {}
	for rule in rules:
		if not (rule is Dictionary):
			continue
		
		var state := String(rule.get("state", ""))
		var input_char := String(rule.get("input", "")).to_lower()
		var output_str := hiragana_katakana_to_hiragana(String(rule.get("output", "")))
		var next_state := String(rule.get("next_state", "default"))
		
		if state.is_empty() or input_char.is_empty():
			continue
		
		if not result.has(state):
			result[state] = {}
		
		result[state][input_char] = {
			"output": output_str,
			"next": next_state,
		}

	# 分割文字スペースは、前チャンクの状態が非defaultでも常に入力可能にする。
	for state_key in result.keys():
		var state := String(state_key)
		if not result[state].has(" "):
			result[state][" "] = {
				"output": " ",
				"next": "default",
			}
	
	return result

# ルビ付き文字列から読み仮名（かな）文字列を取得する。
func ruby_to_hiragana_katakana(text: String) -> String:
	var data := make_sentence_data(text)
	return String(data.get("kana_text", ""))

# ルビ付き文字列から表示用の漢字かな交じり文字列を取得する。
func ruby_to_kanji_kanamajiri(text: String) -> String:
	var data := make_sentence_data(text)
	return String(data.get("kanji_text", ""))

# 文字列中のカタカナをひらがなへ正規化して返す。
func hiragana_katakana_to_hiragana(text: String) -> String:
	var result := ""
	for i in range(text.length()):
		var code := text.unicode_at(i)
		if code >= 0x30A1 and code <= 0x30F6:
			code -= 0x60
		result += String.chr(code)
	return result

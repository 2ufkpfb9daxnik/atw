extends Control

const RECORDS_FILE_PATH := "user://records/records.jsonl"
const GRAPH_HEIGHT := 120.0
const GRAPH_STEP_X := 10.0
const GRAPH_RIGHT_PADDING := 24.0
const GRAPH_MARGIN_LEFT := 34.0
const GRAPH_MARGIN_RIGHT := 10.0
const GRAPH_MARGIN_TOP := 8.0
const GRAPH_MARGIN_BOTTOM := 18.0
const GRAPH_ZOOM_MIN := 0.25
const GRAPH_ZOOM_MAX := 8.0
const GRAPH_ZOOM_STEP := 1.25
const DEFAULT_LIST_PAGE_SIZE := 20
const PAGE_JUMP_STEPS := [16, 8, 4, 2, 1]

var list_scroll: ScrollContainer
var list_vbox: VBoxContainer

var detail_root: Control
var list_back_button: Button
var list_eval_button: Button
var list_open_records_file_button: Button
var detail_back_button: Button
var detail_replay_start_button: Button
var detail_replay_stop_button: Button
var detail_info_vbox: VBoxContainer
var detail_odai_text: RichTextLabel
var detail_replay_log: RichTextLabel
var detail_graph_scroll: ScrollContainer
var detail_graph_canvas: Control
var detail_graph_line: Line2D
var detail_graph_score_per_sec_line: Line2D
var detail_graph_axes: Line2D
var detail_graph_marker: ColorRect
var detail_graph_y_max_label: Label
var detail_graph_y_min_label: Label
var detail_graph_right_y_max_label: Label
var detail_graph_right_y_min_label: Label
var detail_graph_x_start_label: Label
var detail_graph_x_end_label: Label
var detail_graph_zoom_label: Label
var detail_graph_zoom_reset_button: Button
var detail_graph_pos_label: Label
var detail_graph_stats_label: Label
var detail_status_label: Label
var detail_target3_preview: RichTextLabel
var detail_hiragana_preview: RichTextLabel
var detail_history_preview: RichTextLabel

var analytics_root: Control
var analytics_back_button: Button
var analytics_summary_text: RichTextLabel
var analytics_graph_scroll: ScrollContainer
var analytics_graph_canvas: Control
var analytics_score_line: Line2D
var analytics_score_per_sec_line: Line2D
var analytics_miss_rate_line: Line2D
var analytics_legend_label: Label

var replay_running := false
var replay_events: Array[Dictionary] = []
var replay_index := 0
var replay_start_msec := 0
var graph_intervals: Array[float] = []
var graph_max_interval := 1.0
var graph_score_per_sec: Array[float] = []
var graph_max_score_per_sec := 1.0
var graph_zoom := 1.0
var graph_dragging := false
var list_sort_key := "created_at"
var list_sort_desc := true
var list_current_page := 1
var list_page_size := DEFAULT_LIST_PAGE_SIZE
var list_filter_state := {
	"date_from": "",
	"date_to": "",
	"score_min": "",
	"score_max": "",
	"seconds_min": "",
	"seconds_max": "",
	"sps_min": "",
	"sps_max": "",
	"typed_min": "",
	"typed_max": "",
	"miss_min": "",
	"miss_max": "",
	"miss_rate_min": "",
	"miss_rate_max": "",
	"odai_regex": "",
	"layout_regex": "",
}
var list_advanced_query := ""
var list_filter_status_message := ""
var list_filter_inputs: Dictionary = {}
var list_filter_dialog: AcceptDialog
var list_advanced_dialog: AcceptDialog
var list_advanced_query_edit: TextEdit
var list_filter_button: Button
var list_advanced_button: Button

# 記録画面を初期化し、一覧/詳細UIを構築する。
func _ready() -> void:
	list_back_button = find_child("back_button", true, false) as Button
	if list_back_button != null:
		list_back_button.pressed.connect(_on_back_button_pressed)
	list_eval_button = find_child("eval_button", true, false) as Button
	if list_eval_button != null:
		list_eval_button.pressed.connect(_on_eval_button_pressed)
	list_open_records_file_button = find_child("open_records_file_button", true, false) as Button
	if list_open_records_file_button != null:
		list_open_records_file_button.pressed.connect(_on_open_records_file_button_pressed)
	build_list_ui()
	build_detail_ui()
	build_analytics_ui()
	build_filter_dialog()
	build_advanced_search_dialog()
	visibility_changed.connect(_on_visibility_changed)
	set_process_unhandled_input(true)
	update_records_shortcut_labels()

# 記録画面のボタン文言にショートカット表記を付ける。
func update_records_shortcut_labels() -> void:
	if list_back_button != null:
		list_back_button.text = "戻る(B)"
	if list_eval_button != null:
		if can_open_analytics_by_shortcut():
			list_eval_button.text = "評価(A)"
		else:
			list_eval_button.text = "評価"
	if list_filter_button != null:
		if can_open_list_search_shortcut():
			list_filter_button.text = "フィルタ(F)" if not has_active_list_filter() else "フィルタ*(F)"
		else:
			list_filter_button.text = "フィルタ" if not has_active_list_filter() else "フィルタ*"
	if list_advanced_button != null:
		if can_open_list_search_shortcut():
			list_advanced_button.text = "高度な検索(S)" if list_advanced_query.strip_edges().is_empty() else "高度な検索*(S)"
		else:
			list_advanced_button.text = "高度な検索" if list_advanced_query.strip_edges().is_empty() else "高度な検索*"
	if list_open_records_file_button != null:
		list_open_records_file_button.text = "records.jsonlを開く"
	if detail_back_button != null:
		detail_back_button.text = "一覧へ戻る(V)"
	if analytics_back_button != null:
		analytics_back_button.text = "一覧へ戻る(V)"

# recordsファイル（jsonl）を既定アプリで開く。未作成時は保存先フォルダを開く。
func _on_open_records_file_button_pressed() -> void:
	if FileAccess.file_exists(RECORDS_FILE_PATH):
		OS.shell_open(ProjectSettings.globalize_path(RECORDS_FILE_PATH))
		return
	OS.shell_open(ProjectSettings.globalize_path(RECORDS_FILE_PATH.get_base_dir()))

# 一覧表示中で評価ショートカットを受け付けられるか返す。
func can_open_analytics_by_shortcut() -> bool:
	if not visible:
		return false
	if list_scroll == null or not list_scroll.visible:
		return false
	if detail_root != null and detail_root.visible:
		return false
	if analytics_root != null and analytics_root.visible:
		return false
	return true

# 一覧表示中にフィルタ/高度な検索ショートカットを受け付けられるか返す。
func can_open_list_search_shortcut() -> bool:
	if not visible:
		return false
	if list_scroll == null or not list_scroll.visible:
		return false
	if detail_root != null and detail_root.visible:
		return false
	if analytics_root != null and analytics_root.visible:
		return false
	if list_filter_dialog != null and list_filter_dialog.visible:
		return false
	if list_advanced_dialog != null and list_advanced_dialog.visible:
		return false
	return true

# 一覧表示時はメインへ戻り、詳細表示時は一覧へ戻る。
func _on_back_button_pressed() -> void:
	if detail_root != null and detail_root.visible:
		show_list_mode()
		return
	if analytics_root != null and analytics_root.visible:
		show_list_mode()
		return
	visible = false
	get_parent().get_node("main_ui").visible = true

# 詳細の戻るボタンで一覧へ戻る。
func _on_detail_back_pressed() -> void:
	show_list_mode()

# 評価画面の戻るボタンで一覧へ戻る。
func _on_analytics_back_pressed() -> void:
	show_list_mode()

# 一覧の評価ボタン押下で評価画面へ遷移する。
func _on_eval_button_pressed() -> void:
	show_analytics_mode()

# 画面表示時に一覧を更新する。
func _on_visibility_changed() -> void:
	if visible:
		show_list_mode()
		refresh_records_list()

# 再生中なら入力ログを時刻に応じて更新する。
func _process(_delta: float) -> void:
	if not replay_running:
		return
	if detail_replay_log == null:
		replay_running = false
		return

	var elapsed := Time.get_ticks_msec() - replay_start_msec
	while replay_index < replay_events.size():
		var ev := replay_events[replay_index]
		var t_ms := int(ev.get("t_ms", 0))
		if t_ms > elapsed:
			break
		append_replay_event_line(ev, replay_index + 1)
		update_replay_snapshot_preview(ev)
		set_graph_current_index(replay_index)
		replay_index += 1

	if replay_index >= replay_events.size():
		replay_running = false
		if detail_status_label != null:
			detail_status_label.text = "再生完了"
		update_replay_button_labels()

# 詳細表示中は Space で再生/停止をトグルする。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if not key_ev.pressed:
			return
		var repeat := key_ev.echo

		if analytics_root != null and analytics_root.visible:
			if key_ev.keycode == KEY_V and not repeat:
				_on_analytics_back_pressed()
				accept_event()
				return
			return

		if detail_root != null and detail_root.visible:
			if key_ev.keycode == KEY_V and not repeat:
				_on_detail_back_pressed()
				accept_event()
				return
			if key_ev.keycode == KEY_SPACE and not repeat:
				toggle_replay_by_space()
				accept_event()
				return
			if key_ev.keycode == KEY_J:
				move_replay_cursor(-1)
				accept_event()
				return
			if key_ev.keycode == KEY_L:
				move_replay_cursor(1)
				accept_event()
				return
			return

		if key_ev.keycode == KEY_B and not repeat:
			_on_back_button_pressed()
			accept_event()
			return
		if key_ev.keycode == KEY_A and not repeat:
			_on_eval_button_pressed()
			accept_event()
			return
		if key_ev.keycode == KEY_F and not repeat and can_open_list_search_shortcut():
			_on_filter_button_pressed()
			accept_event()
			return
		if key_ev.keycode == KEY_S and not repeat and can_open_list_search_shortcut():
			_on_advanced_search_button_pressed()
			accept_event()


# 評価用UIを作成する。
func build_analytics_ui() -> void:
		analytics_root = VBoxContainer.new()
		analytics_root.name = "analytics_root"
		analytics_root.anchor_left = 0.0
		analytics_root.anchor_top = 0.0
		analytics_root.anchor_right = 1.0
		analytics_root.anchor_bottom = 1.0
		analytics_root.offset_left = 16.0
		analytics_root.offset_top = 40.0
		analytics_root.offset_right = -16.0
		analytics_root.offset_bottom = -16.0
		analytics_root.visible = false
		add_child(analytics_root)

		var top_bar := HFlowContainer.new()
		top_bar.add_theme_constant_override("separation", 8)
		top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		analytics_root.add_child(top_bar)

		analytics_back_button = Button.new()
		analytics_back_button.pressed.connect(_on_analytics_back_pressed)
		top_bar.add_child(analytics_back_button)

		var top_title := Label.new()
		top_title.text = "評価サマリ"
		top_bar.add_child(top_title)

		var body_scroll := ScrollContainer.new()
		body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		analytics_root.add_child(body_scroll)

		var body_vbox := VBoxContainer.new()
		body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body_vbox.add_theme_constant_override("separation", 10)
		body_scroll.add_child(body_vbox)

		analytics_summary_text = RichTextLabel.new()
		analytics_summary_text.fit_content = true
		analytics_summary_text.scroll_active = false
		body_vbox.add_child(analytics_summary_text)

		var graph_title := Label.new()
		graph_title.text = "結果遷移グラフ（時系列順）"
		body_vbox.add_child(graph_title)

		analytics_graph_scroll = ScrollContainer.new()
		analytics_graph_scroll.custom_minimum_size = Vector2(0, 240)
		analytics_graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		analytics_graph_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_vbox.add_child(analytics_graph_scroll)

		analytics_graph_canvas = Control.new()
		analytics_graph_canvas.custom_minimum_size = Vector2(640, 220)
		analytics_graph_scroll.add_child(analytics_graph_canvas)

		analytics_score_line = Line2D.new()
		analytics_score_line.width = 2.0
		analytics_score_line.default_color = Color(0.2, 0.65, 1.0, 0.95)
		analytics_graph_canvas.add_child(analytics_score_line)

		analytics_score_per_sec_line = Line2D.new()
		analytics_score_per_sec_line.width = 2.0
		analytics_score_per_sec_line.default_color = Color(1.0, 0.75, 0.2, 0.95)
		analytics_graph_canvas.add_child(analytics_score_per_sec_line)

		analytics_miss_rate_line = Line2D.new()
		analytics_miss_rate_line.width = 2.0
		analytics_miss_rate_line.default_color = Color(1.0, 0.35, 0.35, 0.95)
		analytics_graph_canvas.add_child(analytics_miss_rate_line)

		analytics_legend_label = Label.new()
		analytics_legend_label.text = "青=スコア, 黄=スコア/秒, 赤=ミス率(%)"
		body_vbox.add_child(analytics_legend_label)

		update_records_shortcut_labels()

# 一覧用UIを作成する。
func build_list_ui() -> void:
	list_scroll = ScrollContainer.new()
	list_scroll.name = "records_scroll"
	list_scroll.anchor_left = 0.0
	list_scroll.anchor_top = 0.0
	list_scroll.anchor_right = 1.0
	list_scroll.anchor_bottom = 1.0
	list_scroll.offset_left = 16.0
	list_scroll.offset_top = 40.0
	list_scroll.offset_right = -16.0
	list_scroll.offset_bottom = -16.0
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(list_scroll)
	move_child(list_scroll, 0)

	list_vbox = VBoxContainer.new()
	list_vbox.name = "records_list_vbox"
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 6)
	list_scroll.add_child(list_vbox)

# 詳細用UIを作成する。
func build_detail_ui() -> void:
	detail_root = VBoxContainer.new()
	detail_root.name = "detail_root"
	detail_root.anchor_left = 0.0
	detail_root.anchor_top = 0.0
	detail_root.anchor_right = 1.0
	detail_root.anchor_bottom = 1.0
	detail_root.offset_left = 16.0
	detail_root.offset_top = 40.0
	detail_root.offset_right = -16.0
	detail_root.offset_bottom = -16.0
	detail_root.visible = false
	add_child(detail_root)

	var top_bar := HFlowContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_root.add_child(top_bar)

	detail_back_button = Button.new()
	detail_back_button.pressed.connect(_on_detail_back_pressed)
	top_bar.add_child(detail_back_button)

	detail_replay_start_button = Button.new()
	detail_replay_start_button.pressed.connect(_on_replay_start_pressed)
	top_bar.add_child(detail_replay_start_button)

	detail_replay_stop_button = Button.new()
	detail_replay_stop_button.pressed.connect(_on_replay_stop_pressed)
	top_bar.add_child(detail_replay_stop_button)

	detail_status_label = Label.new()
	detail_status_label.text = ""
	top_bar.add_child(detail_status_label)

	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_root.add_child(body_scroll)

	var body_vbox := VBoxContainer.new()
	body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_vbox.add_theme_constant_override("separation", 10)
	body_scroll.add_child(body_vbox)

	var top_split := HBoxContainer.new()
	top_split.add_theme_constant_override("separation", 12)
	top_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_vbox.add_child(top_split)

	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	top_split.add_child(left_col)

	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 6)
	top_split.add_child(right_col)

	var info_title := Label.new()
	info_title.text = "記録情報"
	left_col.add_child(info_title)

	detail_info_vbox = VBoxContainer.new()
	detail_info_vbox.add_theme_constant_override("separation", 2)
	left_col.add_child(detail_info_vbox)

	var preview_title := Label.new()
	preview_title.text = "入力時表示再現"
	right_col.add_child(preview_title)

	var target_label_title := Label.new()
	target_label_title.text = "お題文"
	right_col.add_child(target_label_title)
	detail_target3_preview = RichTextLabel.new()
	detail_target3_preview.scroll_active = true
	detail_target3_preview.fit_content = true
	right_col.add_child(detail_target3_preview)

	var hira_label_title := Label.new()
	hira_label_title.text = "ひらがな表示"
	right_col.add_child(hira_label_title)
	detail_hiragana_preview = RichTextLabel.new()
	detail_hiragana_preview.scroll_active = true
	detail_hiragana_preview.fit_content = true
	right_col.add_child(detail_hiragana_preview)

	var history_label_title := Label.new()
	history_label_title.text = "入力履歴"
	right_col.add_child(history_label_title)
	detail_history_preview = RichTextLabel.new()
	detail_history_preview.scroll_active = true
	detail_history_preview.fit_content = true
	right_col.add_child(detail_history_preview)

	var replay_title := Label.new()
	replay_title.text = "入力再現ログ"
	right_col.add_child(replay_title)

	detail_replay_log = RichTextLabel.new()
	detail_replay_log.custom_minimum_size = Vector2(0, 180)
	detail_replay_log.fit_content = false
	detail_replay_log.scroll_active = true
	detail_replay_log.scroll_following = true
	right_col.add_child(detail_replay_log)

	var graph_title := Label.new()
	graph_title.text = "入力間隔(ms) / スコア毎秒 グラフ"
	body_vbox.add_child(graph_title)

	var graph_bar := HBoxContainer.new()
	graph_bar.add_theme_constant_override("separation", 8)
	body_vbox.add_child(graph_bar)

	var zoom_out := Button.new()
	zoom_out.text = "-"
	zoom_out.pressed.connect(_on_graph_zoom_out_pressed)
	graph_bar.add_child(zoom_out)

	detail_graph_zoom_reset_button = Button.new()
	detail_graph_zoom_reset_button.pressed.connect(_on_graph_zoom_reset_pressed)
	graph_bar.add_child(detail_graph_zoom_reset_button)

	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.pressed.connect(_on_graph_zoom_in_pressed)
	graph_bar.add_child(zoom_in)

	detail_graph_zoom_label = Label.new()
	detail_graph_zoom_label.text = "拡大率: 100%"
	graph_bar.add_child(detail_graph_zoom_label)

	detail_graph_pos_label = Label.new()
	detail_graph_pos_label.text = "再生位置(J/L): -"
	graph_bar.add_child(detail_graph_pos_label)

	detail_graph_stats_label = Label.new()
	detail_graph_stats_label.text = ""
	detail_graph_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_graph_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graph_bar.add_child(detail_graph_stats_label)

	var axis_label := Label.new()
	axis_label.text = "縦軸(左): 前の打鍵からの入力間隔(ms) / 縦軸(右): スコア毎秒 / 横軸: 入力順"
	body_vbox.add_child(axis_label)

	var graph_area := HBoxContainer.new()
	graph_area.add_theme_constant_override("separation", 6)
	body_vbox.add_child(graph_area)

	var y_axis_vbox := VBoxContainer.new()
	y_axis_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_area.add_child(y_axis_vbox)

	detail_graph_y_max_label = Label.new()
	detail_graph_y_max_label.text = "0 ms"
	y_axis_vbox.add_child(detail_graph_y_max_label)

	var y_spacer := Control.new()
	y_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	y_axis_vbox.add_child(y_spacer)

	detail_graph_y_min_label = Label.new()
	detail_graph_y_min_label.text = "0 ms"
	y_axis_vbox.add_child(detail_graph_y_min_label)

	detail_graph_scroll = ScrollContainer.new()
	detail_graph_scroll.custom_minimum_size = Vector2(0, GRAPH_HEIGHT + 16.0)
	detail_graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	detail_graph_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_area.add_child(detail_graph_scroll)

	detail_graph_canvas = Control.new()
	detail_graph_canvas.custom_minimum_size = Vector2(320, GRAPH_HEIGHT)
	detail_graph_canvas.gui_input.connect(_on_graph_canvas_gui_input)
	detail_graph_scroll.add_child(detail_graph_canvas)

	detail_graph_axes = Line2D.new()
	detail_graph_axes.width = 1.0
	detail_graph_axes.default_color = Color(0.6, 0.6, 0.6, 0.95)
	detail_graph_canvas.add_child(detail_graph_axes)

	detail_graph_line = Line2D.new()
	detail_graph_line.width = 2.0
	detail_graph_line.default_color = Color(0.2, 0.8, 0.5, 0.95)
	detail_graph_canvas.add_child(detail_graph_line)

	detail_graph_score_per_sec_line = Line2D.new()
	detail_graph_score_per_sec_line.width = 2.0
	detail_graph_score_per_sec_line.default_color = Color(1.0, 0.75, 0.2, 0.95)
	detail_graph_canvas.add_child(detail_graph_score_per_sec_line)

	detail_graph_marker = ColorRect.new()
	detail_graph_marker.color = Color(1.0, 0.3, 0.3, 0.95)
	detail_graph_marker.custom_minimum_size = Vector2(2, GRAPH_HEIGHT)
	detail_graph_canvas.add_child(detail_graph_marker)

	var right_axis_vbox := VBoxContainer.new()
	right_axis_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_area.add_child(right_axis_vbox)

	detail_graph_right_y_max_label = Label.new()
	detail_graph_right_y_max_label.text = "0 /s"
	detail_graph_right_y_max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_axis_vbox.add_child(detail_graph_right_y_max_label)

	var right_spacer := Control.new()
	right_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_axis_vbox.add_child(right_spacer)

	detail_graph_right_y_min_label = Label.new()
	detail_graph_right_y_min_label.text = "0 /s"
	detail_graph_right_y_min_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_axis_vbox.add_child(detail_graph_right_y_min_label)

	var x_axis_row := HBoxContainer.new()
	x_axis_row.add_theme_constant_override("separation", 8)
	body_vbox.add_child(x_axis_row)

	detail_graph_x_start_label = Label.new()
	detail_graph_x_start_label.text = "先頭"
	detail_graph_x_start_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_axis_row.add_child(detail_graph_x_start_label)

	detail_graph_x_end_label = Label.new()
	detail_graph_x_end_label.text = "末尾"
	detail_graph_x_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_graph_x_end_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	x_axis_row.add_child(detail_graph_x_end_label)

	var odai_title := Label.new()
	odai_title.text = "お題（当時の順序で復元）"
	body_vbox.add_child(odai_title)

	detail_odai_text = RichTextLabel.new()
	detail_odai_text.custom_minimum_size = Vector2(0, 120)
	detail_odai_text.fit_content = true
	detail_odai_text.scroll_active = true
	body_vbox.add_child(detail_odai_text)

	update_records_shortcut_labels()
	update_replay_button_labels()

# 一覧表示モードへ切り替える。
func show_list_mode() -> void:
	replay_running = false
	replay_events.clear()
	replay_index = 0
	if detail_root != null:
		detail_root.visible = false
	if analytics_root != null:
		analytics_root.visible = false
	if list_scroll != null:
		list_scroll.visible = true
	update_records_shortcut_labels()

# 詳細表示モードへ切り替えて内容を反映する。
func show_detail_mode(rec: Dictionary) -> void:
	if detail_root == null:
		return
	if list_scroll != null:
		list_scroll.visible = false
	if analytics_root != null:
		analytics_root.visible = false
	detail_root.visible = true
	replay_running = false
	replay_events = get_record_events(rec)
	replay_index = 0
	graph_zoom = 1.0
	graph_dragging = false
	if detail_status_label != null:
		detail_status_label.text = ""
	update_records_shortcut_labels()
	update_replay_button_labels()
	fill_detail_info(rec)
	fill_detail_odai(rec)
	fill_interval_graph(replay_events)
	reset_replay_log(rec)

# 評価表示モードへ切り替え、統計サマリと遷移グラフを更新する。
func show_analytics_mode() -> void:
	if analytics_root == null:
		return
	replay_running = false
	if list_scroll != null:
		list_scroll.visible = false
	if detail_root != null:
		detail_root.visible = false
	analytics_root.visible = true
	update_records_shortcut_labels()

	var records := load_records_jsonl()
	fill_analytics_summary(records)
	fill_analytics_trend_graph(records)

# records.jsonl を読み込み、ヘッダと行を描画する。
func refresh_records_list() -> void:
	if list_vbox == null:
		return

	for c in list_vbox.get_children():
		c.queue_free()

	var all_records := load_records_jsonl()
	var records := sort_records_for_list(apply_active_list_filters(all_records))
	var total_records := records.size()
	var all_records_count := all_records.size()
	var total_pages := get_total_pages(total_records)
	list_current_page = clampi(list_current_page, 1, total_pages)

	add_pagination_block(total_records, all_records_count, total_pages, true)
	add_header_row()

	if records.is_empty():
		var empty_label := Label.new()
		empty_label.text = "記録がありません"
		list_vbox.add_child(empty_label)
		add_pagination_block(total_records, all_records_count, total_pages, false)
		return

	var page_start := (list_current_page - 1) * list_page_size
	var page_end := mini(page_start + list_page_size, total_records)
	for i in range(page_start, page_end):
		add_record_row(records[i])

	add_pagination_block(total_records, all_records_count, total_pages, false)

# 総件数と1ページ件数から総ページ数を返す。
func get_total_pages(total_records: int) -> int:
	if total_records <= 0:
		return 1
	return maxi(1, int(ceil(float(total_records) / float(maxi(list_page_size, 1)))))

# 一覧のページ操作ブロックを追加する。
func add_pagination_block(total_records: int, all_records_count: int, total_pages: int, include_page_size_form: bool) -> void:
	if list_vbox == null:
		return

	if include_page_size_form:
		list_filter_button = null
		list_advanced_button = null
		var config_row := HFlowContainer.new()
		config_row.add_theme_constant_override("separation", 8)
		config_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		config_row.alignment = FlowContainer.ALIGNMENT_BEGIN

		var page_size_label := Label.new()
		page_size_label.text = "1ページ表示件数"
		config_row.add_child(page_size_label)

		var page_size_spin := SpinBox.new()
		page_size_spin.min_value = 1
		page_size_spin.max_value = 1000000
		page_size_spin.step = 1
		page_size_spin.rounded = true
		page_size_spin.value = list_page_size
		page_size_spin.custom_minimum_size = Vector2(96, 0)
		page_size_spin.value_changed.connect(_on_page_size_changed)
		config_row.add_child(page_size_spin)

		list_filter_button = Button.new()
		list_filter_button.pressed.connect(_on_filter_button_pressed)
		config_row.add_child(list_filter_button)

		list_advanced_button = Button.new()
		list_advanced_button.pressed.connect(_on_advanced_search_button_pressed)
		config_row.add_child(list_advanced_button)

		var clear_button := Button.new()
		clear_button.text = "条件クリア"
		clear_button.pressed.connect(_on_clear_filter_button_pressed)
		config_row.add_child(clear_button)

		var config_info := Label.new()
		config_info.text = "表示%d件 / 全%d件  (%dページ)" % [total_records, all_records_count, total_pages]
		if not list_filter_status_message.is_empty():
			config_info.text += "  %s" % list_filter_status_message
		config_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		config_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		config_row.add_child(config_info)
		list_vbox.add_child(config_row)
		update_records_shortcut_labels()

	add_pagination_row(total_pages)

	var sep := HSeparator.new()
	list_vbox.add_child(sep)

# フィルタ条件入力ダイアログを構築する。
func build_filter_dialog() -> void:
	list_filter_dialog = AcceptDialog.new()
	list_filter_dialog.title = "フィルタ"
	list_filter_dialog.min_size = Vector2i(520, 300)
	add_child(list_filter_dialog)
	list_filter_dialog.confirmed.connect(_on_filter_dialog_confirmed)
	list_filter_dialog.get_ok_button().text = "OK"

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 240)
	list_filter_dialog.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(grid)

	add_filter_input_pair(grid, "日時(開始)", "date_from")
	add_filter_input_pair(grid, "日時(終了)", "date_to")
	add_filter_input_pair(grid, "スコア最小", "score_min")
	add_filter_input_pair(grid, "スコア最大", "score_max")
	add_filter_input_pair(grid, "計測秒最小", "seconds_min")
	add_filter_input_pair(grid, "計測秒最大", "seconds_max")
	add_filter_input_pair(grid, "スコア/秒最小", "sps_min")
	add_filter_input_pair(grid, "スコア/秒最大", "sps_max")
	add_filter_input_pair(grid, "入力文字最小", "typed_min")
	add_filter_input_pair(grid, "入力文字最大", "typed_max")
	add_filter_input_pair(grid, "ミス数最小", "miss_min")
	add_filter_input_pair(grid, "ミス数最大", "miss_max")
	add_filter_input_pair(grid, "ミス率%最小", "miss_rate_min")
	add_filter_input_pair(grid, "ミス率%最大", "miss_rate_max")
	add_filter_input_pair(grid, "お題ファイル名", "odai_regex")
	add_filter_input_pair(grid, "配列ファイル名", "layout_regex")

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "空欄は未指定として扱います。日時は created_at の文字列比較で判定します。日付のみで絞る場合は YYYY-MM-DD、時刻まで絞る場合は保存形式に合わせて入力してください。お題ファイル名・配列ファイル名は正規表現で指定できます。"
	root.add_child(hint)

# 高度な検索入力ダイアログを構築する。
func build_advanced_search_dialog() -> void:
	list_advanced_dialog = AcceptDialog.new()
	list_advanced_dialog.title = "高度な検索"
	list_advanced_dialog.min_size = Vector2i(520, 260)
	add_child(list_advanced_dialog)
	list_advanced_dialog.confirmed.connect(_on_advanced_search_confirmed)
	list_advanced_dialog.get_ok_button().text = "OK"

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 180)
	list_advanced_dialog.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var desc := Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.text = "自由語句の検索と、項目比較条件を AND/OR で組み合わせられます。"
	root.add_child(desc)

	list_advanced_query_edit = TextEdit.new()
	list_advanced_query_edit.custom_minimum_size = Vector2(0, 140)
	list_advanced_query_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(list_advanced_query_edit)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "使い方:\n1) 自由語句: qwerty AND test_jp\n2) 数値比較: score>=300 AND miss<10 AND miss_per>2.5\n3) 文字列項目: odai:default AND layout:qwerty\n4) 日時比較: date>=2026-03-01\n対応キー: score, sec, sps, typed, miss, miss_per, date, odai, layout\n演算子: >, >=, <, <=, =, !=\nAND が OR より優先されます。"
	root.add_child(hint)

# フィルタ入力ラベル+フォームを1組追加する。
func add_filter_input_pair(grid: GridContainer, label_text: String, key: String) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var input := LineEdit.new()
	input.placeholder_text = "未指定"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(input)
	list_filter_inputs[key] = input

# フィルタボタン押下でダイアログを開く。
func _on_filter_button_pressed() -> void:
	if list_filter_dialog == null:
		return
	for key in list_filter_inputs.keys():
		var input := list_filter_inputs[key] as LineEdit
		if input != null:
			input.text = String(list_filter_state.get(String(key), ""))
	popup_dialog_with_auto_size(list_filter_dialog, Vector2i(520, 300), 0.86)

# 高度な検索ボタン押下でダイアログを開く。
func _on_advanced_search_button_pressed() -> void:
	if list_advanced_dialog == null:
		return
	if list_advanced_query_edit != null:
		list_advanced_query_edit.text = list_advanced_query
	popup_dialog_with_auto_size(list_advanced_dialog, Vector2i(560, 260), 0.76)

# ダイアログを初回表示でも崩れにくいサイズで中央表示する。
func popup_dialog_with_auto_size(dialog: AcceptDialog, minimum_size: Vector2i, ratio: float) -> void:
	if dialog == null:
		return
	dialog.reset_size()
	var viewport_size := get_viewport_rect().size
	var max_w := maxi(300, int(floor(viewport_size.x * ratio)))
	var max_h := maxi(220, int(floor(viewport_size.y * ratio)))
	var content_min := dialog.get_contents_minimum_size()
	var desired_w := maxi(minimum_size.x, int(ceil(content_min.x)) + 32)
	var desired_h := maxi(minimum_size.y, int(ceil(content_min.y)) + 64)
	var target_w := mini(desired_w, max_w)
	var target_h := mini(desired_h, max_h)
	dialog.popup_centered(Vector2i(target_w, target_h))

# フィルタ確定時に状態を保存して一覧を更新する。
func _on_filter_dialog_confirmed() -> void:
	for key in list_filter_inputs.keys():
		var input := list_filter_inputs[key] as LineEdit
		if input != null:
			list_filter_state[String(key)] = input.text.strip_edges()
	list_current_page = 1
	refresh_records_list()

# 高度な検索確定時に状態を保存して一覧を更新する。
func _on_advanced_search_confirmed() -> void:
	if list_advanced_query_edit != null:
		list_advanced_query = list_advanced_query_edit.text.strip_edges()
	list_current_page = 1
	refresh_records_list()

# 条件クリアボタン押下でフィルタ/高度な検索をすべて解除する。
func _on_clear_filter_button_pressed() -> void:
	for key in list_filter_state.keys():
		list_filter_state[String(key)] = ""
	list_advanced_query = ""
	list_filter_status_message = ""
	list_current_page = 1
	refresh_records_list()

# 何らかのフィルタ条件が有効かを返す。
func has_active_list_filter() -> bool:
	for key in list_filter_state.keys():
		if not String(list_filter_state[key]).strip_edges().is_empty():
			return true
	return false

# ページ番号列（先頭/最終固定 + 2のべき間隔）を描画する。
func add_pagination_row(total_pages: int) -> void:
	if list_vbox == null:
		return

	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = FlowContainer.ALIGNMENT_CENTER

	var pages := build_visible_pages(total_pages)
	for page in pages:
		add_page_button(row, page)

	list_vbox.add_child(row)

# 表示すべきページ番号配列を昇順で返す。
func build_visible_pages(total_pages: int) -> Array[int]:
	var clamped_total := maxi(total_pages, 1)
	var pages: Array[int] = [1, clamped_total, list_current_page]
	for step in PAGE_JUMP_STEPS:
		var step_i := int(step)
		var left := list_current_page - step_i
		var right := list_current_page + step_i
		if left >= 1:
			pages.append(left)
		if right <= clamped_total:
			pages.append(right)

	pages = unique_sorted_pages(pages)
	return pages

# 重複を除去し、昇順ソートして返す。
func unique_sorted_pages(pages: Array[int]) -> Array[int]:
	var seen: Dictionary = {}
	for page in pages:
		seen[page] = true
	var out: Array[int] = []
	for key in seen.keys():
		out.append(int(key))
	out.sort()
	return out

# 1つのページボタンを追加する。現在ページは強調表示する。
func add_page_button(row: Control, page: int) -> void:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	if page == list_current_page:
		button.text = "【%d】" % page
		button.disabled = true
	else:
		button.text = str(page)
		button.pressed.connect(_on_page_button_pressed.bind(page))
	row.add_child(button)

# ページボタン押下で対象ページへ移動する。
func _on_page_button_pressed(page: int) -> void:
	if page == list_current_page:
		return
	list_current_page = maxi(page, 1)
	refresh_records_list()

# 1ページあたり表示件数の入力変更を反映する。
func _on_page_size_changed(value: float) -> void:
	var new_size := maxi(int(round(value)), 1)
	if new_size == list_page_size:
		return
	list_page_size = new_size
	list_current_page = 1
	refresh_records_list()

# 一覧ヘッダ行を追加する。
func add_header_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	add_sort_header_button(row, "日時", 180, "created_at")
	add_sort_header_button(row, "スコア", 70, "score")
	add_sort_header_button(row, "計測秒", 80, "measured_seconds")
	add_sort_header_button(row, "スコア/秒", 80, "score_per_sec")
	add_sort_header_button(row, "入力文字", 80, "typed_chars")
	add_sort_header_button(row, "ミス数", 70, "miss_count")
	add_sort_header_button(row, "ミス率", 80, "miss_rate")
	add_cell(row, "お題", 180)
	add_cell(row, "配列", 140)
	add_cell(row, "操作", 160)

	list_vbox.add_child(row)

	var sep := HSeparator.new()
	list_vbox.add_child(sep)

# ソート可能ヘッダーボタンを追加する。
func add_sort_header_button(row: HBoxContainer, label_text: String, width: float, sort_key: String) -> void:
	var button := Button.new()
	button.text = build_sort_header_text(label_text, sort_key)
	button.custom_minimum_size = Vector2(width, 0)
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_sort_header_pressed.bind(sort_key))
	row.add_child(button)

# ソート対象なら現在の昇降順をヘッダ文言へ反映する。
func build_sort_header_text(label_text: String, sort_key: String) -> String:
	if sort_key != list_sort_key:
		return label_text
	var marker := "v" if list_sort_desc else "^"
	return "%s %s" % [label_text, marker]

# ヘッダ押下時にソートキー/順序を切り替えて一覧を再描画する。
func _on_sort_header_pressed(sort_key: String) -> void:
	if sort_key == list_sort_key:
		list_sort_desc = not list_sort_desc
	else:
		list_sort_key = sort_key
		list_sort_desc = true
	list_current_page = 1
	refresh_records_list()

# 現在のソート設定に基づいてレコード配列を並べ替える。
func sort_records_for_list(records: Array[Dictionary]) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = records.duplicate()
	sorted.sort_custom(Callable(self , "_compare_record_for_list"))
	return sorted

# 現在のフィルタ条件と高度な検索を適用した配列を返す。
func apply_active_list_filters(records: Array[Dictionary]) -> Array[Dictionary]:
	list_filter_status_message = ""
	var invalid_fields: Array[String] = []

	var score_min: Variant = parse_optional_float_bound(String(list_filter_state.get("score_min", "")), "score_min", invalid_fields)
	var score_max: Variant = parse_optional_float_bound(String(list_filter_state.get("score_max", "")), "score_max", invalid_fields)
	var seconds_min: Variant = parse_optional_float_bound(String(list_filter_state.get("seconds_min", "")), "seconds_min", invalid_fields)
	var seconds_max: Variant = parse_optional_float_bound(String(list_filter_state.get("seconds_max", "")), "seconds_max", invalid_fields)
	var sps_min: Variant = parse_optional_float_bound(String(list_filter_state.get("sps_min", "")), "sps_min", invalid_fields)
	var sps_max: Variant = parse_optional_float_bound(String(list_filter_state.get("sps_max", "")), "sps_max", invalid_fields)
	var typed_min: Variant = parse_optional_float_bound(String(list_filter_state.get("typed_min", "")), "typed_min", invalid_fields)
	var typed_max: Variant = parse_optional_float_bound(String(list_filter_state.get("typed_max", "")), "typed_max", invalid_fields)
	var miss_min: Variant = parse_optional_float_bound(String(list_filter_state.get("miss_min", "")), "miss_min", invalid_fields)
	var miss_max: Variant = parse_optional_float_bound(String(list_filter_state.get("miss_max", "")), "miss_max", invalid_fields)
	var miss_rate_min: Variant = parse_optional_float_bound(String(list_filter_state.get("miss_rate_min", "")), "miss_rate_min", invalid_fields)
	var miss_rate_max: Variant = parse_optional_float_bound(String(list_filter_state.get("miss_rate_max", "")), "miss_rate_max", invalid_fields)

	var odai_regex := compile_optional_regex(String(list_filter_state.get("odai_regex", "")), "odai_regex")
	var layout_regex := compile_optional_regex(String(list_filter_state.get("layout_regex", "")), "layout_regex")

	if not invalid_fields.is_empty():
		list_filter_status_message = "数値条件を無視: %s" % ", ".join(invalid_fields)

	var out: Array[Dictionary] = []
	for rec in records:
		var created_at := String(rec.get("created_at", ""))
		if not match_datetime_range(created_at, String(list_filter_state.get("date_from", "")), String(list_filter_state.get("date_to", ""))):
			continue

		var score := float(int(rec.get("score", 0)))
		var seconds := get_record_seconds(rec)
		var typed := float(int(rec.get("typed_chars", 0)))
		var miss := float(int(rec.get("miss_count", 0)))
		var sps := 0.0
		if seconds > 0.0:
			sps = score / seconds
		var miss_rate_percent := 0.0
		if typed > 0.0:
			miss_rate_percent = (miss / typed) * 100.0

		if not value_in_optional_range(score, score_min, score_max):
			continue
		if not value_in_optional_range(seconds, seconds_min, seconds_max):
			continue
		if not value_in_optional_range(sps, sps_min, sps_max):
			continue
		if not value_in_optional_range(typed, typed_min, typed_max):
			continue
		if not value_in_optional_range(miss, miss_min, miss_max):
			continue
		if not value_in_optional_range(miss_rate_percent, miss_rate_min, miss_rate_max):
			continue

		var odai_name := String(rec.get("odai_path", "")).get_file()
		if odai_regex != null and odai_regex.search(odai_name) == null:
			continue
		var layout_name := String(rec.get("layout_path", "")).get_file()
		if layout_regex != null and layout_regex.search(layout_name) == null:
			continue

		if not matches_advanced_query(rec, list_advanced_query):
			continue

		out.append(rec)

	return out

# 空文字なら null、数値なら float、不正なら invalid_fields にキーを積んで null を返す。
func parse_optional_float_bound(text: String, key: String, invalid_fields: Array[String]) -> Variant:
	var t := text.strip_edges()
	if t.is_empty():
		return null
	if not t.is_valid_float() and not t.is_valid_int():
		invalid_fields.append(key)
		return null
	return float(t)

# 空文字なら null、正規表現コンパイル成功で RegEx、失敗時はメッセージを残して null。
func compile_optional_regex(pattern: String, key: String) -> RegEx:
	var p := pattern.strip_edges()
	if p.is_empty():
		return null
	var re := RegEx.new()
	var err := re.compile(p)
	if err != OK:
		if list_filter_status_message.is_empty():
			list_filter_status_message = "%s の正規表現が不正" % key
		else:
			list_filter_status_message += " / %s の正規表現が不正" % key
		return null
	return re

# 片側未指定を許容する範囲判定。
func value_in_optional_range(value: float, min_v: Variant, max_v: Variant) -> bool:
	if min_v != null and value < float(min_v):
		return false
	if max_v != null and value > float(max_v):
		return false
	return true

# created_at を文字列範囲として判定する。日付のみ入力時は先頭10文字で比較する。
func match_datetime_range(created_at: String, date_from: String, date_to: String) -> bool:
	var from_text := date_from.strip_edges()
	if not from_text.is_empty():
		if from_text.length() <= 10:
			var rec_day := created_at.substr(0, mini(created_at.length(), 10))
			if rec_day < from_text:
				return false
		else:
			if created_at < from_text:
				return false

	var to_text := date_to.strip_edges()
	if not to_text.is_empty():
		if to_text.length() <= 10:
			var rec_day2 := created_at.substr(0, mini(created_at.length(), 10))
			if rec_day2 > to_text:
				return false
		else:
			if created_at > to_text:
				return false
	return true

# 高度な検索文字列を AND/OR で評価する。AND 優先、引用符で空白含み語句を指定できる。
func matches_advanced_query(rec: Dictionary, query: String) -> bool:
	var q := query.strip_edges()
	if q.is_empty():
		return true
	var terms := tokenize_advanced_query(q)
	if terms.is_empty():
		return true

	var ctx := build_record_search_context(rec)
	var groups: Array[Array] = []
	var current_group: Array = []

	for term in terms:
		var t := String(term)
		var upper := t.to_upper()
		if upper == "OR":
			if not current_group.is_empty():
				groups.append(current_group.duplicate())
				current_group.clear()
			continue
		if upper == "AND":
			continue
		current_group.append(t.to_lower())

	if not current_group.is_empty():
		groups.append(current_group)

	if groups.is_empty():
		return true

	for group in groups:
		var all_ok := true
		for word in group:
			if not token_matches_record_context(String(word), ctx):
				all_ok = false
				break
		if all_ok:
			return true
	return false

# 高度な検索トークンがレコード条件に一致するか判定する。
func token_matches_record_context(token: String, ctx: Dictionary) -> bool:
	var raw := token.strip_edges()
	if raw.is_empty():
		return true

	var cond := parse_advanced_condition(raw)
	if cond.is_empty():
		var haystack := String(ctx.get("search_text", ""))
		return haystack.find(raw.to_lower()) >= 0

	var key := String(cond.get("key", "")).to_lower()
	var op := String(cond.get("op", ""))
	var rhs := String(cond.get("rhs", "")).strip_edges()
	if rhs.is_empty():
		return true

	var resolved_key := normalize_advanced_key(key)
	if resolved_key.is_empty():
		var haystack2 := String(ctx.get("search_text", ""))
		return haystack2.find(raw.to_lower()) >= 0

	if is_numeric_advanced_key(resolved_key):
		if not rhs.is_valid_float() and not rhs.is_valid_int():
			return false
		var lhs_num := float(ctx.get(resolved_key, 0.0))
		var rhs_num := float(rhs)
		return compare_numeric_condition(lhs_num, rhs_num, op)

	var lhs_text := String(ctx.get(resolved_key, "")).to_lower()
	var rhs_text := rhs.to_lower()
	if op == ":":
		return lhs_text.find(rhs_text) >= 0
	return compare_text_condition(lhs_text, rhs_text, op)

# 高度な検索トークンを key/op/rhs へ分解する。条件式でなければ空辞書を返す。
func parse_advanced_condition(token: String) -> Dictionary:
	var ops := [">=", "<=", "!=", ">", "<", "=", ":"]
	for opv in ops:
		var op := String(opv)
		var idx := token.find(op)
		if idx <= 0:
			continue
		var key := token.substr(0, idx).strip_edges()
		var rhs := token.substr(idx + op.length()).strip_edges()
		if key.is_empty() or rhs.is_empty():
			return {}
		return {"key": key, "op": op, "rhs": rhs}
	return {}

# 高度な検索キーの別名を正規化する。
func normalize_advanced_key(key: String) -> String:
	match key.to_lower():
		"score":
			return "score"
		"sec", "seconds", "time":
			return "sec"
		"sps", "score_per", "score_per_sec":
			return "sps"
		"typed", "chars", "typed_chars":
			return "typed"
		"miss", "miss_count":
			return "miss"
		"miss_per", "miss_rate":
			return "miss_per"
		"date", "created", "created_at":
			return "date"
		"odai", "odai_name":
			return "odai"
		"layout", "layout_name":
			return "layout"
		_:
			return ""

# 数値比較対象キーかを返す。
func is_numeric_advanced_key(key: String) -> bool:
	return key == "score" or key == "sec" or key == "sps" or key == "typed" or key == "miss" or key == "miss_per"

# 数値比較演算子を評価する。
func compare_numeric_condition(lhs: float, rhs: float, op: String) -> bool:
	match op:
		">":
			return lhs > rhs
		">=":
			return lhs >= rhs
		"<":
			return lhs < rhs
		"<=":
			return lhs <= rhs
		"=":
			return is_equal_approx(lhs, rhs)
		"!=":
			return not is_equal_approx(lhs, rhs)
		_:
			return false

# 文字列比較演算子を評価する。
func compare_text_condition(lhs: String, rhs: String, op: String) -> bool:
	match op:
		"=":
			return lhs == rhs
		"!=":
			return lhs != rhs
		">":
			return lhs > rhs
		">=":
			return lhs >= rhs
		"<":
			return lhs < rhs
		"<=":
			return lhs <= rhs
		_:
			return false

# レコードを高度な検索評価用コンテキストへ変換する。
func build_record_search_context(rec: Dictionary) -> Dictionary:
	var created_at := String(rec.get("created_at", ""))
	var score := int(rec.get("score", 0))
	var typed := int(rec.get("typed_chars", 0))
	var miss := int(rec.get("miss_count", 0))
	var seconds := get_record_seconds(rec)
	var sps := 0.0
	if seconds > 0.0:
		sps = float(score) / seconds
	var miss_rate := 0.0
	if typed > 0:
		miss_rate = (float(miss) / float(typed)) * 100.0

	var odai_path := String(rec.get("odai_path", ""))
	var layout_path := String(rec.get("layout_path", ""))
	var odai_name := odai_path.get_file()
	var layout_name := layout_path.get_file()

	return {
		"search_text": build_record_search_text(rec),
		"score": float(score),
		"sec": seconds,
		"sps": sps,
		"typed": float(typed),
		"miss": float(miss),
		"miss_per": miss_rate,
		"date": created_at,
		"odai": odai_name,
		"layout": layout_name,
	}

# 高度な検索のトークン列を作る。"quoted phrase" に対応する。
func tokenize_advanced_query(query: String) -> Array[String]:
	var out: Array[String] = []
	var i := 0
	var n := query.length()
	while i < n:
		while i < n and query[i] == " ":
			i += 1
		if i >= n:
			break
		if query[i] == "\"":
			i += 1
			var start := i
			while i < n and query[i] != "\"":
				i += 1
			var quoted := query.substr(start, i - start)
			if not quoted.is_empty():
				out.append(quoted)
			if i < n and query[i] == "\"":
				i += 1
			continue
		var start2 := i
		while i < n and query[i] != " ":
			i += 1
		var token := query.substr(start2, i - start2)
		if not token.is_empty():
			out.append(token)
	return out

# レコードを検索用の1本文字列へ連結する。
func build_record_search_text(rec: Dictionary) -> String:
	var created_at := String(rec.get("created_at", ""))
	var score := int(rec.get("score", 0))
	var typed := int(rec.get("typed_chars", 0))
	var miss := int(rec.get("miss_count", 0))
	var seconds := get_record_seconds(rec)
	var sps := 0.0
	if seconds > 0.0:
		sps = float(score) / seconds
	var miss_rate := 0.0
	if typed > 0:
		miss_rate = (float(miss) / float(typed)) * 100.0

	var odai_path := String(rec.get("odai_path", ""))
	var layout_path := String(rec.get("layout_path", ""))
	var odai_name := odai_path.get_file()
	var layout_name := layout_path.get_file()

	var text := "%s %s %s %s %s %s %.6f %.6f %.6f %s %s %s %s" % [
		created_at,
		str(score),
		str(typed),
		str(miss),
		("%.6f" % seconds),
		("%.6f" % sps),
		seconds,
		sps,
		miss_rate,
		odai_path,
		odai_name,
		layout_path,
		layout_name,
	]
	return text.to_lower()

# 一覧ソート比較。主キー同値時は日時の新しい順を優先する。
func _compare_record_for_list(a: Dictionary, b: Dictionary) -> bool:
	var cmp := compare_record_sort_key(a, b, list_sort_key)
	if cmp == 0:
		cmp = compare_record_sort_key(a, b, "created_at")
		if cmp == 0:
			var a_id := String(a.get("record_id", ""))
			var b_id := String(b.get("record_id", ""))
			if a_id == b_id:
				return false
			return a_id > b_id
		return cmp > 0
	if list_sort_desc:
		return cmp > 0
	return cmp < 0

# 指定キーで a と b を比較する。a>b なら 1、a<b なら -1、同値なら 0。
func compare_record_sort_key(a: Dictionary, b: Dictionary, key: String) -> int:
	var a_val: Variant = get_record_sort_value(a, key)
	var b_val: Variant = get_record_sort_value(b, key)
	if a_val is String or b_val is String:
		var as_text := String(a_val)
		var bs_text := String(b_val)
		if as_text == bs_text:
			return 0
		return 1 if as_text > bs_text else -1
	var af := float(a_val)
	var bf := float(b_val)
	if is_equal_approx(af, bf):
		return 0
	return 1 if af > bf else -1

# 一覧ソート用の比較値をレコードから取り出す。
func get_record_sort_value(rec: Dictionary, key: String) -> Variant:
	match key:
		"created_at":
			return String(rec.get("created_at", ""))
		"score":
			return float(int(rec.get("score", 0)))
		"measured_seconds":
			return get_record_seconds(rec)
		"score_per_sec":
			var sec := get_record_seconds(rec)
			if sec <= 0.0:
				return 0.0
			return float(int(rec.get("score", 0))) / sec
		"typed_chars":
			return float(int(rec.get("typed_chars", 0)))
		"miss_count":
			return float(int(rec.get("miss_count", 0)))
		"miss_rate":
			var typed := int(rec.get("typed_chars", 0))
			if typed <= 0:
				return 0.0
			return float(int(rec.get("miss_count", 0))) / float(typed)
		_:
			return String(rec.get("created_at", ""))

# レコード1件分の表示行を追加する。
func add_record_row(rec: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var created_at := String(rec.get("created_at", ""))
	var score := int(rec.get("score", 0))
	var typed_chars := int(rec.get("typed_chars", 0))
	var miss_count := int(rec.get("miss_count", 0))
	var seconds := get_record_seconds(rec)
	var measured_text := "%.2f" % seconds
	var score_per_sec := 0.0
	if seconds > 0.0:
		score_per_sec = float(score) / seconds
	var miss_rate := 0.0
	if typed_chars > 0:
		miss_rate = float(miss_count) / float(typed_chars)

	var odai_name := String(rec.get("odai_path", "")).get_file()
	var layout_name := String(rec.get("layout_path", "")).get_file()

	add_cell(row, created_at, 180)
	add_cell(row, str(score), 70)
	add_cell(row, measured_text, 80)
	add_cell(row, "%.2f" % score_per_sec, 80)
	add_cell(row, str(typed_chars), 80)
	add_cell(row, str(miss_count), 70)
	add_cell(row, "%.1f%%" % (miss_rate * 100.0), 80)
	add_cell(row, odai_name, 180)
	add_cell(row, layout_name, 140)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.custom_minimum_size = Vector2(156, 0)

	var detail_btn := Button.new()
	detail_btn.text = "詳細"
	detail_btn.custom_minimum_size = Vector2(72, 0)
	detail_btn.pressed.connect(_on_detail_pressed.bind(rec))
	actions.add_child(detail_btn)

	var delete_btn := Button.new()
	delete_btn.text = "削除"
	delete_btn.custom_minimum_size = Vector2(72, 0)
	delete_btn.pressed.connect(_on_delete_pressed.bind(rec))
	actions.add_child(delete_btn)

	row.add_child(actions)

	list_vbox.add_child(row)

# 評価サマリ文章を構築して表示する。
func fill_analytics_summary(records_newest_first: Array[Dictionary]) -> void:
	if analytics_summary_text == null:
		return
	analytics_summary_text.clear()
	if records_newest_first.is_empty():
		analytics_summary_text.append_text("記録がないため評価を表示できません。")
		return

	var total_rounds := records_newest_first.size()
	var total_score := 0
	var total_chars := 0
	var total_miss := 0
	var total_seconds := 0.0
	var best_score := -2147483648
	var worst_score := 2147483647
	var best_score_at := ""
	var worst_score_at := ""

	var layout_count: Dictionary = {}
	var odai_count: Dictionary = {}
	var day_count: Dictionary = {}
	var day_score_sum: Dictionary = {}

	for rec in records_newest_first:
		var score := int(rec.get("score", 0))
		var typed := int(rec.get("typed_chars", 0))
		var miss := int(rec.get("miss_count", 0))
		var sec := get_record_seconds(rec)
		var created := String(rec.get("created_at", ""))
		var day := created.substr(0, mini(created.length(), 10))

		total_score += score
		total_chars += typed
		total_miss += miss
		total_seconds += sec
		if score > best_score:
			best_score = score
			best_score_at = created
		if score < worst_score:
			worst_score = score
			worst_score_at = created

		var layout_key := String(rec.get("layout_path", "")).get_file()
		if layout_key.is_empty():
			layout_key = "(unknown)"
		layout_count[layout_key] = int(layout_count.get(layout_key, 0)) + 1

		var odai_key := String(rec.get("odai_path", "")).get_file()
		if odai_key.is_empty():
			odai_key = "(unknown)"
		odai_count[odai_key] = int(odai_count.get(odai_key, 0)) + 1

		if day.is_empty():
			day = "(unknown day)"
		day_count[day] = int(day_count.get(day, 0)) + 1
		day_score_sum[day] = int(day_score_sum.get(day, 0)) + score

	var avg_score := float(total_score) / float(max(total_rounds, 1))
	var avg_chars := float(total_chars) / float(max(total_rounds, 1))
	var avg_miss := float(total_miss) / float(max(total_rounds, 1))
	var avg_score_per_sec := 0.0
	var avg_chars_per_sec := 0.0
	if total_seconds > 0.0:
		avg_score_per_sec = float(total_score) / total_seconds
		avg_chars_per_sec = float(total_chars) / total_seconds
	var avg_miss_rate := 0.0
	if total_chars > 0:
		avg_miss_rate = float(total_miss) / float(total_chars)

	var newest_at := String(records_newest_first[0].get("created_at", ""))
	var oldest_at := String(records_newest_first[records_newest_first.size() - 1].get("created_at", ""))

	analytics_summary_text.append_text("【全体】\n")
	analytics_summary_text.append_text("記録数: %d\n" % total_rounds)
	analytics_summary_text.append_text("期間: %s 〜 %s\n" % [oldest_at, newest_at])
	analytics_summary_text.append_text("総スコア: %d  /  平均スコア: %.2f\n" % [total_score, avg_score])
	analytics_summary_text.append_text("総入力文字: %d  /  平均入力文字: %.2f\n" % [total_chars, avg_chars])
	analytics_summary_text.append_text("総ミス: %d  /  平均ミス: %.2f\n" % [total_miss, avg_miss])
	analytics_summary_text.append_text("平均スコア/秒: %.3f\n" % avg_score_per_sec)
	analytics_summary_text.append_text("平均入力文字/秒: %.3f\n" % avg_chars_per_sec)
	analytics_summary_text.append_text("平均ミス率: %.2f%%\n" % (avg_miss_rate * 100.0))
	analytics_summary_text.append_text("最高スコア: %d (%s)\n" % [best_score, best_score_at])
	analytics_summary_text.append_text("最低スコア: %d (%s)\n\n" % [worst_score, worst_score_at])

	analytics_summary_text.append_text("【配列の使用回数】\n")
	append_top_counts(analytics_summary_text, layout_count, 20)
	analytics_summary_text.append_text("\n【お題ファイルの使用回数】\n")
	append_top_counts(analytics_summary_text, odai_count, 20)

	analytics_summary_text.append_text("\n【日別の回数と平均スコア】\n")
	var days := day_count.keys()
	days.sort()
	for day in days:
		var c := int(day_count[day])
		var ssum := int(day_score_sum.get(day, 0))
		var avg_s := float(ssum) / float(max(c, 1))
		analytics_summary_text.append_text("%s : %d回, 平均スコア %.2f\n" % [String(day), c, avg_s])

	analytics_summary_text.append_text("\n【直近10件】\n")
	for i in range(mini(records_newest_first.size(), 10)):
		var rec := records_newest_first[i]
		var sec := get_record_seconds(rec)
		var score := int(rec.get("score", 0))
		var miss := int(rec.get("miss_count", 0))
		var typed := int(rec.get("typed_chars", 0))
		var miss_rate := 0.0
		if typed > 0:
			miss_rate = float(miss) / float(typed)
		analytics_summary_text.append_text("%s  score=%d  sec=%.2f  miss=%d  miss_rate=%.1f%%\n" % [String(rec.get("created_at", "")), score, sec, miss, miss_rate * 100.0])

# キーごとの回数辞書を多い順で追記する。
func append_top_counts(out: RichTextLabel, counter: Dictionary, limit: int) -> void:
	if counter.is_empty():
		out.append_text("(データなし)\n")
		return
	var entries: Array[Dictionary] = []
	for key in counter.keys():
		entries.append({"key": String(key), "count": int(counter[key])})
	entries.sort_custom(Callable(self , "_compare_count_entry"))
	for i in range(mini(entries.size(), limit)):
		var e := entries[i]
		out.append_text("%s : %d回\n" % [String(e.get("key", "")), int(e.get("count", 0))])

# 回数辞書のソート用比較（多い順、同数ならキー昇順）。
func _compare_count_entry(a: Dictionary, b: Dictionary) -> bool:
	var ac := int(a.get("count", 0))
	var bc := int(b.get("count", 0))
	if ac == bc:
		return String(a.get("key", "")) < String(b.get("key", ""))
	return ac > bc

# 時系列レコードから結果遷移グラフを描画する。
func fill_analytics_trend_graph(records_newest_first: Array[Dictionary]) -> void:
	if analytics_graph_canvas == null or analytics_score_line == null or analytics_score_per_sec_line == null or analytics_miss_rate_line == null:
		return
	analytics_score_line.clear_points()
	analytics_score_per_sec_line.clear_points()
	analytics_miss_rate_line.clear_points()

	if records_newest_first.is_empty():
		analytics_graph_canvas.custom_minimum_size = Vector2(640, 220)
		if analytics_legend_label != null:
			analytics_legend_label.text = "青=スコア, 黄=スコア/秒, 赤=ミス率(%)"
		return

	var records_oldest := records_newest_first.duplicate()
	records_oldest.reverse()

	var scores: Array[float] = []
	var score_per_secs: Array[float] = []
	var miss_rates: Array[float] = []
	var max_score := 1.0
	var max_sps := 1.0
	var max_miss := 1.0

	for rec in records_oldest:
		var score := float(int(rec.get("score", 0)))
		var typed := int(rec.get("typed_chars", 0))
		var miss := int(rec.get("miss_count", 0))
		var sec := get_record_seconds(rec)
		var sps := 0.0
		if sec > 0.0:
			sps = score / sec
		var miss_rate := 0.0
		if typed > 0:
			miss_rate = (float(miss) / float(typed)) * 100.0

		scores.append(score)
		score_per_secs.append(sps)
		miss_rates.append(miss_rate)
		max_score = maxf(max_score, score)
		max_sps = maxf(max_sps, sps)
		max_miss = maxf(max_miss, miss_rate)

	var margin_left := 20.0
	var margin_right := 12.0
	var margin_top := 10.0
	var margin_bottom := 18.0
	var graph_h := 220.0
	var plot_h := graph_h - margin_top - margin_bottom
	var step_x := 18.0
	var width := maxi(int(margin_left + margin_right + float(max(scores.size() - 1, 1)) * step_x), 640)
	analytics_graph_canvas.custom_minimum_size = Vector2(width, graph_h)

	for i in range(scores.size()):
		var x := margin_left + float(i) * step_x
		var score_y := margin_top + plot_h * (1.0 - (scores[i] / max_score))
		var sps_y := margin_top + plot_h * (1.0 - (score_per_secs[i] / max_sps))
		var miss_y := margin_top + plot_h * (1.0 - (miss_rates[i] / max_miss))
		analytics_score_line.add_point(Vector2(x, score_y))
		analytics_score_per_sec_line.add_point(Vector2(x, sps_y))
		analytics_miss_rate_line.add_point(Vector2(x, miss_y))

	if analytics_legend_label != null:
		analytics_legend_label.text = "青=スコア(max %.1f), 黄=スコア/秒(max %.2f), 赤=ミス率%%(max %.1f)" % [max_score, max_sps, max_miss]

# 固定幅ラベルセルを追加する。
func add_cell(row: HBoxContainer, text: String, width: float) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(label)

# 詳細ボタン押下時に詳細画面へ遷移する。
func _on_detail_pressed(rec: Dictionary) -> void:
	show_detail_mode(rec)

# 削除ボタン押下時に records.jsonl から対象レコードを削除する。
func _on_delete_pressed(rec: Dictionary) -> void:
	var records := load_records_jsonl()
	if records.is_empty():
		return

	var filtered: Array[Dictionary] = []
	var removed := false
	for item in records:
		if not removed and is_same_record(item, rec):
			removed = true
			continue
		filtered.append(item)

	if not removed:
		return
	if not save_records_jsonl(filtered):
		if detail_status_label != null:
			detail_status_label.text = "削除に失敗しました"
		return

	show_list_mode()
	refresh_records_list()

# 再生ボタン押下で入力イベント再生を開始する。
func _on_replay_start_pressed() -> void:
	start_replay(true)

# 停止ボタン押下で入力イベント再生を停止する。
func _on_replay_stop_pressed() -> void:
	stop_replay("停止")

# Space 用トグル: 再生中は停止、停止中は現在位置から再開する。
func toggle_replay_by_space() -> void:
	if replay_running:
		stop_replay("停止 (Space)")
		return
	start_replay(false)

# 再生を開始する。from_beginning=true なら先頭から、false なら現在位置から再開する。
func start_replay(from_beginning: bool) -> void:
	if replay_events.is_empty():
		if detail_status_label != null:
			detail_status_label.text = "入力イベントがありません"
		update_replay_button_labels()
		return

	if from_beginning:
		replay_index = 0
		if detail_replay_log != null:
			detail_replay_log.clear()
		if detail_graph_scroll != null:
			detail_graph_scroll.scroll_horizontal = 0
		update_replay_snapshot_preview(replay_events[0])
		set_graph_current_index(0)
	elif replay_index >= replay_events.size():
		replay_index = replay_events.size() - 1

	var base_ms := 0
	if replay_index > 0 and replay_index - 1 < replay_events.size():
		base_ms = int((replay_events[replay_index - 1] as Dictionary).get("t_ms", 0))
	replay_start_msec = Time.get_ticks_msec() - base_ms
	replay_running = true
	if detail_status_label != null:
		detail_status_label.text = "再生中"
	update_replay_button_labels()

# 再生を停止し、状態テキストとラベルを更新する。
func stop_replay(status_text: String) -> void:
	replay_running = false
	if detail_status_label != null:
		detail_status_label.text = status_text
	update_replay_button_labels()

# 再生/停止ボタンの表示を現在状態に合わせて更新する。
func update_replay_button_labels() -> void:
	if detail_replay_start_button != null:
		detail_replay_start_button.text = "再生(Space)"
	if detail_replay_stop_button != null:
		if replay_running:
			detail_replay_stop_button.text = "停止(Spaceで停止)"
		else:
			detail_replay_stop_button.text = "停止(Space)"
	if detail_graph_pos_label != null and replay_events.is_empty():
		detail_graph_pos_label.text = "再生位置(J/L): -"

# 再生ログを初期状態で表示する。
func reset_replay_log(rec: Dictionary) -> void:
	if detail_replay_log == null:
		return
	detail_replay_log.clear()
	detail_replay_log.append_text("入力イベント数: %d\n" % get_record_events(rec).size())
	detail_replay_log.append_text("再生ボタンまたは Space で時系列再現します。\n")
	var events := get_record_events(rec)
	if not events.is_empty():
		update_replay_snapshot_preview(events[0])
		set_graph_current_index(0)

# 再生ログに1イベント分を追記する。
func append_replay_event_line(ev: Dictionary, idx: int) -> void:
	if detail_replay_log == null:
		return
	var t_ms := int(ev.get("t_ms", 0))
	var key := String(ev.get("key", ""))
	var ok := bool(ev.get("ok", false))
	var expected_target := String(ev.get("expected_target", ""))
	var status := "OK" if ok else "MISS"
	var line := "%04d  %6dms  key=%s  %s  target=%s\n" % [idx, t_ms, key, status, expected_target]
	if ok:
		detail_replay_log.push_color(Color(0.2, 0.5, 1.0, 1.0))
	else:
		detail_replay_log.push_color(Color(1.0, 0.25, 0.25, 1.0))
	detail_replay_log.append_text(line)
	detail_replay_log.pop()
	detail_replay_log.scroll_to_line(detail_replay_log.get_line_count())

# 詳細情報欄にレコードの各種情報を表示する。
func fill_detail_info(rec: Dictionary) -> void:
	if detail_info_vbox == null:
		return
	for c in detail_info_vbox.get_children():
		c.queue_free()

	var score := int(rec.get("score", 0))
	var typed_chars := int(rec.get("typed_chars", 0))
	var miss_count := int(rec.get("miss_count", 0))
	var seconds := get_record_seconds(rec)
	var miss_rate := 0.0
	if typed_chars > 0:
		miss_rate = float(miss_count) / float(typed_chars)
	var score_per_sec := 0.0
	if seconds > 0.0:
		score_per_sec = float(score) / seconds

	add_info_line("日時", String(rec.get("created_at", "")))
	add_info_line("record_id", String(rec.get("record_id", "")))
	add_info_line("スコア", str(score))
	add_info_line("計測秒", "%.2f" % seconds)
	add_info_line("スコア/秒", "%.2f" % score_per_sec)
	add_info_line("入力文字数", str(typed_chars))
	add_info_line("ミス数", str(miss_count))
	add_info_line("ミス率", "%.2f%%" % (miss_rate * 100.0))
	add_info_line("お題ファイル", String(rec.get("odai_path", "")))
	add_info_line("配列ファイル", String(rec.get("layout_path", "")))
	add_info_line("設定計測秒", str(int(rec.get("round_seconds", 0))))
	add_info_line("開始前カウントダウン秒", str(int(rec.get("countdown_seconds", 0))))
	add_info_line("入力イベント数", str(get_record_events(rec).size()))

# 詳細情報欄に1行を追加する。
func add_info_line(key: String, value: String) -> void:
	if detail_info_vbox == null:
		return
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var key_label := Label.new()
	key_label.text = key
	key_label.custom_minimum_size = Vector2(170, 0)
	line.add_child(key_label)
	var val_label := Label.new()
	val_label.text = value
	line.add_child(val_label)
	detail_info_vbox.add_child(line)

# お題スナップショットを復元して表示する。
func fill_detail_odai(rec: Dictionary) -> void:
	if detail_odai_text == null:
		return
	detail_odai_text.clear()
	var lines := reconstruct_odai_lines(rec)
	if lines.is_empty():
		detail_odai_text.append_text("(保存されたお題情報がありません)")
		return
	for i in range(lines.size()):
		detail_odai_text.append_text("%d. %s\n" % [i + 1, lines[i]])

# 入力間隔の折れ線グラフを作成する。
func fill_interval_graph(events: Array[Dictionary]) -> void:
	if detail_graph_canvas == null or detail_graph_line == null or detail_graph_score_per_sec_line == null or detail_graph_axes == null:
		return
	graph_intervals = build_intervals_ms(events)
	graph_score_per_sec = build_score_per_sec_series(events)
	graph_max_interval = 1.0
	for v in graph_intervals:
		graph_max_interval = maxf(graph_max_interval, float(v))
	graph_max_score_per_sec = 1.0
	for v in graph_score_per_sec:
		graph_max_score_per_sec = maxf(graph_max_score_per_sec, float(v))
	redraw_graph()

# 現在のズーム率とデータに合わせて折れ線・軸・マーカーを再描画する。
func redraw_graph() -> void:
	if detail_graph_canvas == null or detail_graph_line == null or detail_graph_score_per_sec_line == null or detail_graph_axes == null:
		return
	detail_graph_line.clear_points()
	detail_graph_score_per_sec_line.clear_points()
	detail_graph_axes.clear_points()
	if detail_graph_marker != null:
		detail_graph_marker.visible = false

	if detail_graph_zoom_label != null:
		detail_graph_zoom_label.text = "拡大率: %d%%" % int(round(graph_zoom * 100.0))
	if detail_graph_zoom_reset_button != null:
		detail_graph_zoom_reset_button.text = "%d%%" % int(round(graph_zoom * 100.0))

	if graph_intervals.is_empty():
		detail_graph_canvas.custom_minimum_size = Vector2(320, GRAPH_HEIGHT)
		update_graph_axis_labels(1.0, 1.0, 0)
		return

	var data_points := graph_intervals.size()
	var step := get_graph_step_x(data_points)
	var width := maxi(int(GRAPH_MARGIN_LEFT + GRAPH_MARGIN_RIGHT + float(max(data_points - 1, 0)) * step), 320)
	detail_graph_canvas.custom_minimum_size = Vector2(width, GRAPH_HEIGHT)

	var bottom_y := GRAPH_HEIGHT - GRAPH_MARGIN_BOTTOM
	var plot_h := maxf(bottom_y - GRAPH_MARGIN_TOP, 1.0)

	detail_graph_axes.add_point(Vector2(GRAPH_MARGIN_LEFT, GRAPH_MARGIN_TOP))
	detail_graph_axes.add_point(Vector2(GRAPH_MARGIN_LEFT, bottom_y))
	detail_graph_axes.add_point(Vector2(width - GRAPH_MARGIN_RIGHT, bottom_y))

	for i in range(graph_intervals.size()):
		var v := float(graph_intervals[i])
		var ratio := v / graph_max_interval
		var x := GRAPH_MARGIN_LEFT + float(i) * step
		var y := bottom_y - (plot_h * ratio)
		detail_graph_line.add_point(Vector2(x, y))

	for i in range(graph_score_per_sec.size()):
		var v_sps := float(graph_score_per_sec[i])
		var ratio_sps := v_sps / graph_max_score_per_sec
		var x_sps := GRAPH_MARGIN_LEFT + float(i) * step
		var y_sps := bottom_y - (plot_h * ratio_sps)
		detail_graph_score_per_sec_line.add_point(Vector2(x_sps, y_sps))

	update_graph_axis_labels(graph_max_interval, graph_max_score_per_sec, replay_events.size())
	if not replay_events.is_empty():
		set_graph_current_index(maxi(replay_index - 1, 0), false)

# 軸ラベルを最新のスケールとデータ数に合わせて更新する。
func update_graph_axis_labels(max_interval: float, max_score_per_sec: float, event_count: int) -> void:
	if detail_graph_y_max_label != null:
		detail_graph_y_max_label.text = "%.0f ms" % max_interval
	if detail_graph_y_min_label != null:
		detail_graph_y_min_label.text = "0 ms"
	if detail_graph_right_y_max_label != null:
		detail_graph_right_y_max_label.text = "%.2f /s" % max_score_per_sec
	if detail_graph_right_y_min_label != null:
		detail_graph_right_y_min_label.text = "0 /s"
	if detail_graph_x_start_label != null:
		detail_graph_x_start_label.text = "1打鍵目"
	if detail_graph_x_end_label != null:
		detail_graph_x_end_label.text = "%d打鍵目" % max(event_count, 1)

# 現在の表示幅とズーム率から点間隔を計算する。
func get_graph_step_x(point_count: int) -> float:
	if point_count <= 1:
		return GRAPH_STEP_X * graph_zoom
	var viewport_w := 320.0
	if detail_graph_scroll != null:
		viewport_w = maxf(detail_graph_scroll.size.x, 320.0)
	var usable_w := maxf(viewport_w - GRAPH_MARGIN_LEFT - GRAPH_MARGIN_RIGHT, 80.0)
	var fit_step := usable_w / float(point_count - 1)
	return maxf(fit_step * graph_zoom, 1.0)

# 再生中にグラフを現在位置まで自動スクロールする。
func auto_scroll_graph_to_index(event_index: int) -> void:
	if detail_graph_scroll == null:
		return
	var x := int(get_graph_x_for_event_index(event_index))
	var viewport_w := int(detail_graph_scroll.size.x)
	var target := x - viewport_w + int(GRAPH_RIGHT_PADDING)
	detail_graph_scroll.scroll_horizontal = maxi(target, 0)

# グラフ上で現在再生位置を更新し、必要なら右端追従スクロールする。
func set_graph_current_index(event_index: int, follow_scroll := true) -> void:
	if replay_events.is_empty() or detail_graph_marker == null:
		if detail_graph_pos_label != null:
			detail_graph_pos_label.text = "再生位置: -"
		if detail_graph_stats_label != null:
			detail_graph_stats_label.text = ""
		return
	var clamped := clampi(event_index, 0, replay_events.size() - 1)
	var x := get_graph_x_for_event_index(clamped)
	detail_graph_marker.visible = true
	detail_graph_marker.position = Vector2(x - 1.0, 0.0)
	detail_graph_marker.size = Vector2(2.0, GRAPH_HEIGHT)
	if detail_graph_pos_label != null:
		var t_ms := int((replay_events[clamped] as Dictionary).get("t_ms", 0))
		detail_graph_pos_label.text = "再生位置(J/L): %d/%d  (%dms)" % [clamped + 1, replay_events.size(), t_ms]
	update_replay_stats_label(clamped)
	if follow_scroll:
		auto_scroll_graph_to_index(clamped)

# 指定時点までのイベントから統計を作成して表示する。
func update_replay_stats_label(event_index: int) -> void:
	if detail_graph_stats_label == null:
		return
	if replay_events.is_empty():
		detail_graph_stats_label.text = ""
		return

	var limit := clampi(event_index, 0, replay_events.size() - 1)
	var typed := limit + 1
	var miss := 0
	for i in range(limit + 1):
		if not bool((replay_events[i] as Dictionary).get("ok", false)):
			miss += 1
	var score := typed - miss
	var elapsed_sec := float(int((replay_events[limit] as Dictionary).get("t_ms", 0))) / 1000.0
	var score_per_sec := 0.0
	var chars_per_sec := 0.0
	if elapsed_sec > 0.0:
		score_per_sec = float(score) / elapsed_sec
		chars_per_sec = float(typed) / elapsed_sec
	var miss_rate := 0.0
	if typed > 0:
		miss_rate = float(miss) / float(typed)

	detail_graph_stats_label.text = "スコア:%d  スコア/秒:%.2f  文字/秒:%.2f  ミス:%d  ミス率:%.1f%%" % [score, score_per_sec, chars_per_sec, miss, miss_rate * 100.0]

# イベント番号から現在ズームでの描画X座標を返す。
func get_graph_x_for_event_index(event_index: int) -> float:
	if replay_events.size() <= 1:
		return GRAPH_MARGIN_LEFT
	var point_count := maxi(graph_intervals.size(), 1)
	var step := get_graph_step_x(point_count)
	var interval_index := maxi(event_index - 1, 0)
	return GRAPH_MARGIN_LEFT + float(interval_index) * step

# X座標から最寄りのイベント番号へ変換する。
func get_event_index_from_graph_x(x: float) -> int:
	if replay_events.is_empty():
		return 0
	if replay_events.size() <= 1:
		return 0
	var point_count := maxi(graph_intervals.size(), 1)
	var step := get_graph_step_x(point_count)
	var interval_f := (x - GRAPH_MARGIN_LEFT) / maxf(step, 1.0)
	var interval_i := clampi(int(round(interval_f)), 0, max(graph_intervals.size() - 1, 0))
	return clampi(interval_i + 1, 0, replay_events.size() - 1)

# グラフをドラッグして再生位置を移動する。
func _on_graph_canvas_gui_input(event: InputEvent) -> void:
	if replay_events.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			graph_dragging = mb.pressed
			if mb.pressed:
				seek_replay_to_graph_x(mb.position.x)
				accept_event()
	elif event is InputEventMouseMotion:
		if graph_dragging:
			var mm := event as InputEventMouseMotion
			seek_replay_to_graph_x(mm.position.x)
			accept_event()

# グラフX座標を再生位置へ反映する。
func seek_replay_to_graph_x(x: float) -> void:
	if replay_events.is_empty():
		return
	var idx := get_event_index_from_graph_x(x)
	seek_replay_to_index(idx)

# 指定イベント番号へ再生位置を移動する。
func seek_replay_to_index(idx: int) -> void:
	if replay_events.is_empty():
		return
	var clamped := clampi(idx, 0, replay_events.size() - 1)
	replay_index = clamped + 1
	rebuild_replay_log_to_index(clamped)
	update_replay_snapshot_preview(replay_events[clamped])
	set_graph_current_index(clamped)
	if replay_running:
		replay_start_msec = Time.get_ticks_msec() - int((replay_events[clamped] as Dictionary).get("t_ms", 0))

# 現在の再生位置を基準に、前後へ1イベント移動する。
func move_replay_cursor(delta: int) -> void:
	if replay_events.is_empty():
		return
	var current := get_current_replay_event_index()
	seek_replay_to_index(current + delta)

# 現在表示中のイベント番号を返す。
func get_current_replay_event_index() -> int:
	if replay_events.is_empty():
		return 0
	if replay_index <= 0:
		return 0
	return clampi(replay_index - 1, 0, replay_events.size() - 1)

# 指定位置までログを再構築して表示する。
func rebuild_replay_log_to_index(event_index: int) -> void:
	if detail_replay_log == null:
		return
	detail_replay_log.clear()
	detail_replay_log.append_text("入力イベント数: %d\n" % replay_events.size())
	var limit := clampi(event_index, 0, replay_events.size() - 1)
	for i in range(limit + 1):
		append_replay_event_line(replay_events[i], i + 1)

# 拡大ボタン: 横方向ズームを上げる。
func _on_graph_zoom_in_pressed() -> void:
	graph_zoom = minf(graph_zoom * GRAPH_ZOOM_STEP, GRAPH_ZOOM_MAX)
	redraw_graph()

# 縮小ボタン: 横方向ズームを下げる。
func _on_graph_zoom_out_pressed() -> void:
	graph_zoom = maxf(graph_zoom / GRAPH_ZOOM_STEP, GRAPH_ZOOM_MIN)
	redraw_graph()

# 100%ボタン: 端から端までフィット表示へ戻す。
func _on_graph_zoom_reset_pressed() -> void:
	graph_zoom = 1.0
	redraw_graph()

# 入力イベントに保存された当時の表示状態を3ボックスへ反映する。
func update_replay_snapshot_preview(ev: Dictionary) -> void:
	var target_text := String(ev.get("snap_target3", ""))
	var hira_text := String(ev.get("snap_hiragana", ""))
	var history_text := String(ev.get("snap_history", ""))
	if target_text.is_empty():
		target_text = "(この記録には target_text3 スナップショットがありません)"
	if hira_text.is_empty():
		hira_text = "(この記録には hiragana_box スナップショットがありません)"
	if history_text.is_empty():
		history_text = "(この記録には history_box スナップショットがありません)"

	if detail_target3_preview != null:
		detail_target3_preview.clear()
		detail_target3_preview.append_text(target_text)
	if detail_hiragana_preview != null:
		detail_hiragana_preview.clear()
		detail_hiragana_preview.append_text(hira_text)
	if detail_history_preview != null:
		detail_history_preview.clear()
		detail_history_preview.append_text(history_text)

# 入力イベント列から連続入力間隔(ms)を生成する。
func build_intervals_ms(events: Array[Dictionary]) -> Array[float]:
	var result: Array[float] = []
	if events.size() <= 1:
		return result
	var prev := float((events[0] as Dictionary).get("t_ms", 0.0))
	for i in range(1, events.size()):
		if not (events[i] is Dictionary):
			continue
		var curr := float((events[i] as Dictionary).get("t_ms", prev))
		result.append(maxf(curr - prev, 0.0))
		prev = curr
	return result

# 各時点(2打鍵目以降)のスコア/秒を系列化する。
func build_score_per_sec_series(events: Array[Dictionary]) -> Array[float]:
	var result: Array[float] = []
	if events.size() <= 1:
		return result

	var miss := 0
	for i in range(events.size()):
		var ev := events[i] as Dictionary
		if not bool(ev.get("ok", false)):
			miss += 1
		if i == 0:
			continue
		var typed := i + 1
		var score := typed - miss
		var elapsed_sec := float(int(ev.get("t_ms", 0))) / 1000.0
		var sps := 0.0
		if elapsed_sec > 0.0:
			sps = float(score) / elapsed_sec
		result.append(maxf(sps, 0.0))
	return result

# レコードの入力イベント配列を安全に取得する。
func get_record_events(rec: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var events_variant: Variant = rec.get("input_events", [])
	if not (events_variant is Array):
		return out
	for ev in events_variant as Array:
		if ev is Dictionary:
			out.append(ev as Dictionary)
	return out

# 記録に保存されたお題スナップショットを順序復元して返す。
func reconstruct_odai_lines(rec: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var snap_variant: Variant = rec.get("odai_snapshot", {})
	if not (snap_variant is Dictionary):
		return result
	var snap := snap_variant as Dictionary

	var unique_variant: Variant = snap.get("unique_lines", [])
	var order_variant: Variant = snap.get("line_order", [])
	if not (unique_variant is Array and order_variant is Array):
		return result

	var unique_arr := unique_variant as Array
	var order_arr := order_variant as Array
	for idx_v in order_arr:
		var idx := int(idx_v)
		if idx >= 0 and idx < unique_arr.size():
			result.append(String(unique_arr[idx]))
	return result

# records.jsonl を新しい順で読み込んで返す。
func load_records_jsonl() -> Array[Dictionary]:
	if not FileAccess.file_exists(RECORDS_FILE_PATH):
		return []

	var file := FileAccess.open(RECORDS_FILE_PATH, FileAccess.READ)
	if file == null:
		return []

	var result: Array[Dictionary] = []
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var json := JSON.new()
		var err := json.parse(line)
		if err != OK:
			continue
		if json.data is Dictionary:
			result.append(json.data as Dictionary)

	file.close()
	result.reverse()
	return result

# 新しい順の配列を records.jsonl へ保存する。
func save_records_jsonl(records_newest_first: Array[Dictionary]) -> bool:
	var dir_path := RECORDS_FILE_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return false

	var file := FileAccess.open(RECORDS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		return false

	for i in range(records_newest_first.size() - 1, -1, -1):
		file.store_line(JSON.stringify(records_newest_first[i]))

	file.close()
	return true

# 同一レコード判定。record_id を優先し、古い記録は主要項目で照合する。
func is_same_record(a: Dictionary, b: Dictionary) -> bool:
	var a_id := String(a.get("record_id", ""))
	var b_id := String(b.get("record_id", ""))
	if not a_id.is_empty() and not b_id.is_empty():
		return a_id == b_id

	if String(a.get("created_at", "")) != String(b.get("created_at", "")):
		return false
	if int(a.get("score", 0)) != int(b.get("score", 0)):
		return false
	if int(a.get("typed_chars", 0)) != int(b.get("typed_chars", 0)):
		return false
	if int(a.get("miss_count", 0)) != int(b.get("miss_count", 0)):
		return false
	if String(a.get("odai_path", "")) != String(b.get("odai_path", "")):
		return false
	if String(a.get("layout_path", "")) != String(b.get("layout_path", "")):
		return false

	var a_events := get_record_events(a).size()
	var b_events := get_record_events(b).size()
	return a_events == b_events

# 秒あたりスコア計算用の分母秒数をレコードから取得する。
func get_record_seconds(rec: Dictionary) -> float:
	if rec.has("measured_seconds"):
		var measured := float(rec.get("measured_seconds", 0.0))
		if measured > 0.0:
			return measured

	if rec.has("round_seconds"):
		var v := float(rec.get("round_seconds", 0.0))
		if v > 0.0:
			return v

	var events_variant: Variant = rec.get("input_events", [])
	if events_variant is Array:
		var events := events_variant as Array
		if not events.is_empty() and events[events.size() - 1] is Dictionary:
			var last_event := events[events.size() - 1] as Dictionary
			var t_ms := float(last_event.get("t_ms", 0.0))
			if t_ms > 0.0:
				return t_ms / 1000.0

	return 0.0

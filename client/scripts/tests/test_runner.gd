extends SceneTree

# =====================================================================
#             WAYFINDER AUTOMATED GDSCRIPT TEST RUNNER
# =====================================================================
# Executes test scripts in res://scripts/tests/ sequentially via headless
# Godot subprocesses, collects exit codes & stdout/stderr, and outputs a
# clear test summary table and GitHub Actions Markdown summary.
#
# Usage:
#   godot --headless -s res://scripts/tests/test_runner.gd
# Optional flags:
#   --filter=<substring>         Run tests containing substring
#   --summary-file=<path>        Path to write Markdown summary
#   --skip-network-if-offline    Skip live backend tests if localhost:8080 offline
# =====================================================================

const TESTS_DIR: String = "res://scripts/tests"
const KNOWN_NETWORK_TESTS: Array[String] = [
	"checkout_test.gd",
	"integration_test.gd",
	"launch_test.gd"
]

var tests_to_run: Array[String] = []
var explicit_tests: Array[String] = []
var results: Array[Dictionary] = []
var summary_file_path: String = ""
var filter_pattern: String = ""
var skip_network_if_offline: bool = true

func _init() -> void:
	_parse_arguments()
	_run_all_tests.call_deferred()

func _parse_arguments() -> void:
	var args = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--filter="):
			filter_pattern = arg.substr("--filter=".length()).strip_edges()
		elif arg.begins_with("--test=") or arg.begins_with("--tests="):
			var val = arg.substr(arg.find("=") + 1).strip_edges()
			for t in val.split(","):
				var clean_t = t.strip_edges()
				if clean_t != "":
					if not clean_t.ends_with(".gd"):
						clean_t += ".gd"
					explicit_tests.append(clean_t)
		elif arg.begins_with("--summary-file="):
			summary_file_path = arg.substr("--summary-file=".length()).strip_edges()
		elif arg == "--no-skip-network":
			skip_network_if_offline = false

func _run_all_tests() -> void:
	print("\n==================================================================")
	print("       WAYFINDER / LODESTONE GDSCRIPT CI TEST HARNESS             ")
	print("==================================================================")
	print("Godot Binary : ", OS.get_executable_path())
	print("Project Path : ", ProjectSettings.globalize_path("res://"))
	
	# 1. Check if local backend is listening on 8080
	var backend_online = _check_backend_online()
	print("Backend Status: %s (ws://localhost:8080)" % ["ONLINE" if backend_online else "OFFLINE"])
	
	# 2. Discover test scripts
	_discover_tests()
	print("Discovered   : %d test script(s) to execute\n" % tests_to_run.size())
	
	var godot_bin = OS.get_executable_path()
	var proj_path = ProjectSettings.globalize_path("res://")
	var total_passed = 0
	var total_failed = 0
	var total_skipped = 0
	
	var overall_start = Time.get_ticks_msec()
	
	# 3. Sequentially execute each test
	for i in range(tests_to_run.size()):
		var test_file = tests_to_run[i]
		var idx = i + 1
		var test_res_path = TESTS_DIR + "/" + test_file
		
		# Check if network test should be skipped when offline
		if skip_network_if_offline and not backend_online and test_file in KNOWN_NETWORK_TESTS:
			print("[%d/%d] ⚠️  SKIPPED: %s (backend offline on localhost:8080)" % [idx, tests_to_run.size(), test_file])
			results.append({
				"name": test_file,
				"status": "SKIPPED",
				"exit_code": 0,
				"duration": 0.0,
				"log": "Skipped because localhost:8080 backend is not running."
			})
			total_skipped += 1
			continue
		
		print("[%d/%d] RUNNING: %s..." % [idx, tests_to_run.size(), test_file])
		var start_time = Time.get_ticks_msec()
		
		var output: Array = []
		var exec_args = [
			"--headless",
			"--path", proj_path,
			"-s", test_res_path
		]
		
		var exit_code = OS.execute(godot_bin, exec_args, output, true)
		var duration = (Time.get_ticks_msec() - start_time) / 1000.0
		var raw_log = output[0] if output.size() > 0 else ""
		
		if exit_code == 0:
			print("       ✅ PASS: %s (%.2fs)" % [test_file, duration])
			results.append({
				"name": test_file,
				"status": "PASSED",
				"exit_code": 0,
				"duration": duration,
				"log": raw_log
			})
			total_passed += 1
		else:
			print("       ❌ FAIL: %s (Exit Code: %d, %.2fs)" % [test_file, exit_code, duration])
			_print_log_tail(raw_log)
			results.append({
				"name": test_file,
				"status": "FAILED",
				"exit_code": exit_code,
				"duration": duration,
				"log": raw_log
			})
			total_failed += 1
	
	var total_duration = (Time.get_ticks_msec() - overall_start) / 1000.0
	
	# 4. Print console summary
	print("\n==================================================================")
	print("                         TEST RUN SUMMARY                         ")
	print("==================================================================")
	print(" Total Tests : %d" % tests_to_run.size())
	print(" Passed      : %d" % total_passed)
	print(" Failed      : %d" % total_failed)
	print(" Skipped     : %d" % total_skipped)
	print(" Total Time  : %.2f seconds" % total_duration)
	print("==================================================================")
	
	if total_failed > 0:
		print("\nFailed Tests:")
		for r in results:
			if r["status"] == "FAILED":
				print(" - %s (Exit code: %d)" % [r["name"], r["exit_code"]])
		print("")
	
	# 5. Write Markdown summary if requested
	if summary_file_path != "":
		_write_markdown_summary(summary_file_path, total_passed, total_failed, total_skipped, total_duration)
	
	# 6. Exit with appropriate code
	quit(1 if total_failed > 0 else 0)

func _discover_tests() -> void:
	tests_to_run.clear()
	if explicit_tests.size() > 0:
		for t in explicit_tests:
			if FileAccess.file_exists(TESTS_DIR + "/" + t):
				tests_to_run.append(t)
			else:
				printerr("Warning: Specified test not found on disk: ", TESTS_DIR + "/" + t)
		return

	var dir = DirAccess.open(TESTS_DIR)
	if not dir:
		printerr("Failed to open tests directory: ", TESTS_DIR)
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".gd"):
			# Exclude self and non-test helpers
			if file_name != "test_runner.gd" and not file_name.begins_with("_"):
				if filter_pattern == "" or filter_pattern in file_name:
					tests_to_run.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	tests_to_run.sort()

func _check_backend_online() -> bool:
	var tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host("127.0.0.1", 8080)
	if err != OK:
		return false
	
	var start = Time.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - start > 500:
			tcp.disconnect_from_host()
			return false
		OS.delay_msec(20)
		tcp.poll()
		
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		tcp.disconnect_from_host()
		return false

	# Send minimal HTTP request to verify a live server is actually responding
	var req = "GET /api/games HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
	tcp.put_data(req.to_utf8_buffer())
	start = Time.get_ticks_msec()
	while tcp.get_available_bytes() == 0:
		if Time.get_ticks_msec() - start > 600:
			tcp.disconnect_from_host()
			return false
		OS.delay_msec(20)
		tcp.poll()
		
	var resp = tcp.get_utf8_string(tcp.get_available_bytes())
	tcp.disconnect_from_host()
	return resp.begins_with("HTTP/1.1 200") or resp.begins_with("HTTP/1.0 200")

func _print_log_tail(log_str: String, line_count: int = 15) -> void:
	var lines = log_str.split("\n")
	var start_idx = max(0, lines.size() - line_count)
	print("       --- Log Snippet (Last %d lines) ---" % min(line_count, lines.size()))
	for k in range(start_idx, lines.size()):
		var line = lines[k].strip_edges()
		if line != "":
			print("       | " + line)
	print("       ------------------------------------")

func _write_markdown_summary(path: String, passed: int, failed: int, skipped: int, duration: float) -> void:
	var md = ""
	md += "## 🎮 Godot GDScript Test Results\n\n"
	
	var status_badge = "✅ **All Tests Passed**" if failed == 0 else "❌ **%d Test(s) Failed**" % failed
	md += "%s\n\n" % status_badge
	md += "| Metric | Count |\n"
	md += "| :--- | :--- |\n"
	md += "| **Total Tests** | %d |\n" % (passed + failed + skipped)
	md += "| **Passed** | %d |\n" % passed
	md += "| **Failed** | %d |\n" % failed
	md += "| **Skipped** | %d |\n" % skipped
	md += "| **Execution Duration** | %.2fs |\n\n" % duration
	
	md += "### Test Breakdown\n\n"
	md += "| Status | Test Script | Duration | Exit Code |\n"
	md += "| :---: | :--- | :---: | :---: |\n"
	for r in results:
		var badge = "✅ Pass"
		if r["status"] == "FAILED":
			badge = "❌ Fail"
		elif r["status"] == "SKIPPED":
			badge = "⚠️ Skipped"
		md += "| %s | `%s` | %.2fs | `%d` |\n" % [badge, r["name"], r["duration"], r["exit_code"]]
	
	if failed > 0:
		md += "\n### 🔍 Failure Details\n\n"
		for r in results:
			if r["status"] == "FAILED":
				md += "<details><summary><b>%s</b> (Exit code %d)</summary>\n\n" % [r["name"], r["exit_code"]]
				md += "```text\n"
				md += r["log"].strip_edges()
				md += "\n```\n\n</details>\n\n"
	
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(md)
		f.close()
		print("Wrote test summary Markdown to: %s" % path)
	else:
		printerr("Failed to write test summary Markdown to: %s" % path)

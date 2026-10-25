class_name ProcessLauncher
extends RefCounted

func launch(node: Node, executable_path: String, args: Array, tag: String = "Client") -> int:
	print("[Launcher] Spawning process: ", executable_path, " with args: ", args)
	var pipe_data: Dictionary = OS.execute_with_pipe(executable_path, args)
	if not pipe_data.has("pid") or pipe_data["pid"] <= 0:
		print("[Launcher Error] Failed to spawn process: ", executable_path)
		return -1
	var process_id: int = pipe_data["pid"]
	print("[Launcher] Spawned ", tag, " process with PID: ", process_id)
	var stdout_pipe: FileAccess = pipe_data.get("stdout")
	var stderr_pipe: FileAccess = pipe_data.get("stderr")
	if stdout_pipe or stderr_pipe:
		WorkerThreadPool.add_task(func():
			_read_pipe_logs(stdout_pipe, stderr_pipe, tag)
		)
	return process_id

func _read_pipe_logs(stdout_pipe: FileAccess, stderr_pipe: FileAccess, tag: String) -> void:
	while (stdout_pipe and stdout_pipe.is_open()) or (stderr_pipe and stderr_pipe.is_open()):
		var read_anything: bool = false
		if stdout_pipe and stdout_pipe.is_open():
			if stdout_pipe.eof_reached() or stdout_pipe.get_error() != OK:
				stdout_pipe.close()
				stdout_pipe = null
			else:
				var output_line: String = stdout_pipe.get_line()
				if output_line != "":
					print("[" + tag + " Output] " + output_line)
					read_anything = true
				if stdout_pipe.eof_reached() or stdout_pipe.get_error() != OK:
					stdout_pipe.close()
					stdout_pipe = null
		if stderr_pipe and stderr_pipe.is_open():
			if stderr_pipe.eof_reached() or stderr_pipe.get_error() != OK:
				stderr_pipe.close()
				stderr_pipe = null
			else:
				var error_line: String = stderr_pipe.get_line()
				if error_line != "":
					print("[" + tag + " Error Log] " + error_line)
					read_anything = true
				if stderr_pipe.eof_reached() or stderr_pipe.get_error() != OK:
					stderr_pipe.close()
					stderr_pipe = null
		if not read_anything and (stdout_pipe != null or stderr_pipe != null):
			OS.delay_msec(100)

class_name SaveManager
extends RefCounted

static func checkout_save(node: Node, room_code: String, user_id: String, btn: Button, status_callback: Callable) -> void:
	print("[Checkout] Initiating save checkout from server...")
	status_callback.call("Checking out save...")
	if btn:
		btn.disabled = true
		
	var http = HTTPRequest.new()
	node.add_child(http)
	
	var download_dir = "user://saves/".path_join(room_code)
	DirAccess.make_dir_recursive_absolute(download_dir)
	var temp_zip_path = download_dir.path_join("save_download.zip")
	
	http.download_file = temp_zip_path
	
	http.request_completed.connect(func(result, response_code, headers, body):
		http.queue_free()
		if btn:
			btn.disabled = false
			
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[Checkout Error] HTTP request failed.")
			status_callback.call("Checkout Failed: Connection error")
			return
			
		if response_code == 409:
			print("[Checkout Conflict] Session is locked by another user.")
			status_callback.call("Checkout Conflict: Locked by another player")
			return
		elif response_code != 200:
			print("[Checkout Error] Server returned code: ", response_code)
			status_callback.call("Checkout Failed (HTTP " + str(response_code) + ")")
			return
			
		var is_json_response: bool = false
		for h in headers:
			if h.to_lower().begins_with("content-type:") and "application/json" in h.to_lower():
				is_json_response = true
				break

		if not is_json_response:
			var file = FileAccess.open(temp_zip_path, FileAccess.READ)
			if file:
				var magic: PackedByteArray = file.get_buffer(2)
				file.close()
				if magic.size() < 2 or magic[0] != 0x50 or magic[1] != 0x4B:
					is_json_response = true

		if is_json_response:
			print("[Checkout] Locked session successfully; starting fresh (no remote save file exists).")
			status_callback.call("Session Checked Out (New Save)")
			DirAccess.remove_absolute(temp_zip_path)
			return
				
		var err = extract_checkout_save(temp_zip_path, download_dir)
		if err == OK:
			print("[Checkout] Save file checked out and extracted to: ", download_dir)
			status_callback.call("Save Checked Out Successfully")
		else:
			print("[Checkout Error] Failed to extract save ZIP. Error code: ", err)
			status_callback.call("Checkout Error: Extraction failed")
			
		DirAccess.remove_absolute(temp_zip_path)
	)
	
	var url = NetworkManager.get_http_url() + "/api/session/" + room_code + "/checkout?userId=" + user_id
	http.request(url)

static func extract_checkout_save(zip_path: String, dest_dir: String) -> Error:
	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	if err != OK:
		return err
		
	var files = reader.get_files()
	for f in files:
		var data = reader.read_file(f)
		var file = FileAccess.open(dest_dir.path_join(f), FileAccess.WRITE)
		if file:
			file.store_buffer(data)
			file.close()
			
	reader.close()
	return OK

static func checkin_save(node: Node, room_code: String, user_id: String, btn: Button, status_callback: Callable) -> void:
	print("[Checkin] Packing and uploading local save...")
	status_callback.call("Checking in save...")
	if btn:
		btn.disabled = true
		
	var save_dir = "user://saves/".path_join(room_code)
	var save_path = save_dir.path_join(room_code + ".apsave")
	
	if not FileAccess.file_exists(save_path):
		print("[Checkin Error] Save file not found locally: ", save_path)
		status_callback.call("Checkin Error: No local save file found")
		if btn:
			btn.disabled = false
		return
		
	var upload_zip_path = save_dir.path_join("save_upload.zip")
	
	var packer = ZIPPacker.new()
	var err = packer.open(upload_zip_path, ZIPPacker.APPEND_CREATE)
	if err != OK:
		print("[Checkin Error] Failed to create ZIP archive.")
		status_callback.call("Checkin Error: Compression failed")
		if btn:
			btn.disabled = false
		return
		
	var file = FileAccess.open(save_path, FileAccess.READ)
	if not file:
		print("[Checkin Error] Failed to read save file.")
		status_callback.call("Checkin Error: Failed to read save")
		packer.close()
		if btn:
			btn.disabled = false
		return
		
	var buffer = file.get_buffer(file.get_length())
	file.close()
	
	packer.start_file(room_code + ".apsave")
	packer.write_file(buffer)
	packer.close_file()
	packer.close()
	
	var zip_file = FileAccess.open(upload_zip_path, FileAccess.READ)
	if not zip_file:
		print("[Checkin Error] Failed to read zip for upload.")
		status_callback.call("Checkin Error: Failed to open archive")
		if btn:
			btn.disabled = false
		return
		
	var zip_data = zip_file.get_buffer(zip_file.get_length())
	zip_file.close()
	
	var http = HTTPRequest.new()
	node.add_child(http)
	
	http.request_completed.connect(func(result, response_code, headers, body):
		http.queue_free()
		if btn:
			btn.disabled = false
		DirAccess.remove_absolute(upload_zip_path)
		
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[Checkin Error] HTTP upload failed.")
			status_callback.call("Checkin Error: Upload connection failed")
			return
			
		if response_code == 200:
			print("[Checkin] Save file uploaded and unlocked successfully.")
			status_callback.call("Save Checked In Successfully")
		else:
			print("[Checkin Error] Upload failed with code: ", response_code)
			status_callback.call("Checkin Error (HTTP " + str(response_code) + ")")
	)
	
	var url = NetworkManager.get_http_url() + "/api/session/" + room_code + "/checkin?userId=" + user_id
	var headers = ["Content-Type: application/zip"]
	http.request_raw(url, headers, HTTPClient.METHOD_POST, zip_data)

static func force_unlock_session(node: Node, room_code: String, user_id: String, btn: Button, status_callback: Callable) -> void:
	print("[Force Unlock] Requesting session lock bypass...")
	status_callback.call("Force unlocking session...")
	if btn:
		btn.disabled = true
		
	var http = HTTPRequest.new()
	node.add_child(http)
	
	http.request_completed.connect(func(result, response_code, headers, body):
		http.queue_free()
		if btn:
			btn.disabled = false
			
		if result != HTTPRequest.RESULT_SUCCESS:
			print("[Unlock Error] HTTP request failed.")
			status_callback.call("Force Unlock Failed: Connection error")
			return
			
		if response_code == 200:
			print("[Force Unlock] Session lock broken successfully.")
			status_callback.call("Session Unlocked")
		else:
			print("[Unlock Error] Server returned code: ", response_code)
			status_callback.call("Force Unlock Error (HTTP " + str(response_code) + ")")
	)
	
	var url = NetworkManager.get_http_url() + "/api/session/" + room_code + "/unlock?userId=" + user_id
	http.request(url, [], HTTPClient.METHOD_POST)

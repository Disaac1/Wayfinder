class_name Updater
extends RefCounted

const BASE_VERSION: String = "1.0.4"
static var active_version: String = BASE_VERSION

const UPDATE_PCK_PATH: String = "user://update.pck"
const UPDATE_META_PATH: String = "user://update_meta.json"
const UPDATE_TEMP_PATH: String = "user://update.pck.tmp"

# Embedded RSA-2048 public key for cryptographic signature verification.
# Only packages signed by the corresponding private key can be mounted.
const PUBLIC_KEY_PEM: String = """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlks8vqYcFTLFNRlrTPup
L3lV7YCz9EVDCJmigVorirTMTKzBJucp7zqlca+62Wx5DpCcymV7JY+CdAvcEVTQ
HkNuiDUv4YPwzvzafMeJg62/cnAatleANXD79ef1kBB7rKe4OgEkRW6b5YHxzCi4
QsickiX+K7WEhYyICeKT9BthwzNgyGa8XEhMZyly/7NL7cbWKTPrs9sMbmffVH8j
Qj9lmkqZp1LeLxH5/pOFNQets7wS2esfAY1gGWAhk+h8l14nqyNAngxb28j+LhWj
5b/ON6uEYKzsmAITMR0B711tlksakK6kTnnpp/dYv5ZdkDxrelyAcQbTvBgBL+HH
JQIDAQAB
-----END PUBLIC KEY-----"""

# Static helper to compare semantic versions (e.g., "1.0.1" > "1.0.0")
static func is_version_newer(remote: String, local: String = "") -> bool:
	if local.is_empty():
		local = active_version
	var r_parts = remote.split(".")
	var l_parts = local.split(".")
	var max_len = max(r_parts.size(), l_parts.size())
	for i in range(max_len):
		var r_num = int(r_parts[i]) if i < r_parts.size() else 0
		var l_num = int(l_parts[i]) if i < l_parts.size() else 0
		if r_num > l_num:
			return true
		elif r_num < l_num:
			return false
	return false

# Helper to detect whether the client is running in a development / editor environment
static func is_dev_environment() -> bool:
	# 1. Running inside the Godot Editor
	if OS.has_feature("editor"):
		return true
	# 2. Running directly from project files rather than an exported template binary
	if not OS.has_feature("template"):
		return true
	# 3. Environment variable override
	if OS.has_environment("WAYFINDER_DEV") and OS.get_environment("WAYFINDER_DEV") == "1":
		return true
	return false

# Early boot verification: mounts verified updates on engine startup
static func bootstrap_early_updates() -> void:
	if is_dev_environment():
		print("[Updater] Development environment detected. Skipping mounting update.pck.")
		return

	if not FileAccess.file_exists(UPDATE_PCK_PATH) or not FileAccess.file_exists(UPDATE_META_PATH):
		return
		
	var meta_file = FileAccess.open(UPDATE_META_PATH, FileAccess.READ)
	if not meta_file:
		return
	var meta_text = meta_file.get_as_text()
	meta_file.close()
	
	var meta = JSON.parse_string(meta_text)
	if not (meta is Dictionary) or not meta.has("version"):
		_cleanup_update_files()
		return
		
	var patch_ver = meta.get("version", "")
	# If base installer was updated to match or exceed this patch, remove obsolete patch
	if not is_version_newer(patch_ver, BASE_VERSION):
		print("[Updater] Base version (v", BASE_VERSION, ") supersedes patch (v", patch_ver, "). Cleaning up patch.")
		_cleanup_update_files()
		return
		
	var expected_sha = meta.get("sha256", "")
	var sig_b64 = meta.get("signature", "")
	
	var check = verify_pck(UPDATE_PCK_PATH, expected_sha, sig_b64)
	if not check.get("valid", false):
		push_warning("[Updater] Stored update.pck failed security verification: " + str(check.get("error", "")))
		_cleanup_update_files()
		return
		
	var success = ProjectSettings.load_resource_pack(UPDATE_PCK_PATH, true)
	if success:
		active_version = patch_ver
		print("[Updater] Successfully mounted verified patch: v", active_version)
	else:
		push_warning("[Updater] Failed to mount update.pck")

static func _cleanup_update_files() -> void:
	if FileAccess.file_exists(UPDATE_PCK_PATH):
		DirAccess.remove_absolute(UPDATE_PCK_PATH)
	if FileAccess.file_exists(UPDATE_META_PATH):
		DirAccess.remove_absolute(UPDATE_META_PATH)
	if FileAccess.file_exists(UPDATE_TEMP_PATH):
		DirAccess.remove_absolute(UPDATE_TEMP_PATH)

# Verifies SHA-256 and cryptographic RSA signature against the embedded public key
static func verify_pck(pck_path: String, expected_sha256: String, signature_b64: String) -> Dictionary:
	var file = FileAccess.open(pck_path, FileAccess.READ)
	if not file:
		return {"valid": false, "error": "Unable to read package file"}
		
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var chunk = file.get_buffer(65536)
		if chunk.size() > 0:
			ctx.update(chunk)
	file.close()
	
	var raw_hash: PackedByteArray = ctx.finish()
	var computed_hex: String = raw_hash.hex_encode()
	
	if expected_sha256 != "" and computed_hex.to_lower() != expected_sha256.to_lower():
		return {
			"valid": false,
			"error": "Checksum mismatch! Expected: " + expected_sha256 + " Computed: " + computed_hex
		}
		
	if signature_b64.is_empty():
		return {"valid": false, "error": "Package is unsigned"}
		
	var sig_bytes = Marshalls.base64_to_raw(signature_b64)
	if sig_bytes.is_empty():
		return {"valid": false, "error": "Invalid base64 signature"}
		
	var pub_key = CryptoKey.new()
	var err = pub_key.load_from_string(PUBLIC_KEY_PEM, true)
	if err != OK:
		return {"valid": false, "error": "Internal error loading public key"}
		
	var crypto = Crypto.new()
	var is_verified = crypto.verify(HashingContext.HASH_SHA256, raw_hash, sig_bytes, pub_key)
	if not is_verified:
		return {"valid": false, "error": "Digital signature verification failed! Package may be modified or untrusted."}
		
	return {"valid": true, "error": ""}

static func get_server_base_url(node: Node = null) -> String:
	if node and is_instance_valid(node) and node.is_inside_tree():
		var nm = node.get_tree().root.get_node_or_null("NetworkManager")
		if nm and nm.has_method("get_http_url"):
			return nm.get_http_url()
	return "https://wayfinder.disaac1.com"

# Check if an update is available on the backend server
static func check_for_update(node: Node, callback: Callable) -> void:
	if is_dev_environment():
		print("[Updater] Development environment detected. Auto-update check disabled.")
		callback.call(false, {})
		return

	var http = HTTPRequest.new()
	http.timeout = 3.0
	node.add_child(http)
	
	var url = get_server_base_url(node) + "/api/client/version"
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			callback.call(false, {})
			return
			
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary and parsed.has("version"):
			var remote_version = parsed.get("version", "1.0.0")
			var has_update = is_version_newer(remote_version, active_version)
			callback.call(has_update, parsed)
		else:
			callback.call(false, {})
	)
	
	var err = http.request(url)
	if err != OK:
		http.queue_free()
		callback.call(false, {})

# Download new .pck file from server, verify signature, and load dynamically
static func apply_update(node: Node, update_info: Dictionary, progress_callback: Callable, completed_callback: Callable) -> void:
	if is_dev_environment():
		completed_callback.call(false, "Update mounting is disabled in development mode")
		return

	var http = HTTPRequest.new()
	http.use_threads = true
	http.download_chunk_size = 1048576 # 1 MB buffer for fast downloads
	node.add_child(http)
	
	var download_url_rel = update_info.get("download_url", "/api/client/download-pck")
	var target_version = update_info.get("version", "")
	var expected_sha256 = update_info.get("sha256", "")
	var signature_b64 = update_info.get("signature", "")
	
	var download_url = get_server_base_url(node) + download_url_rel
	http.download_file = UPDATE_TEMP_PATH
	
	# Cleanup any previous partial temp file
	if FileAccess.file_exists(UPDATE_TEMP_PATH):
		DirAccess.remove_absolute(UPDATE_TEMP_PATH)
		
	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if FileAccess.file_exists(UPDATE_TEMP_PATH):
				DirAccess.remove_absolute(UPDATE_TEMP_PATH)
			completed_callback.call(false, "Download failed with HTTP " + str(response_code))
			return
			
		if not FileAccess.file_exists(UPDATE_TEMP_PATH):
			completed_callback.call(false, "Downloaded file not found on disk")
			return
			
		# Step 1: Verify cryptographic signature and SHA-256
		var verify_result = verify_pck(UPDATE_TEMP_PATH, expected_sha256, signature_b64)
		if not verify_result.get("valid", false):
			DirAccess.remove_absolute(UPDATE_TEMP_PATH)
			var err_msg = str(verify_result.get("error", "Signature verification failed"))
			push_error("[Updater] " + err_msg)
			completed_callback.call(false, err_msg)
			return
			
		# Step 2: Swap temp file into live update file
		if FileAccess.file_exists(UPDATE_PCK_PATH):
			DirAccess.remove_absolute(UPDATE_PCK_PATH)
		var rename_err = DirAccess.rename_absolute(UPDATE_TEMP_PATH, UPDATE_PCK_PATH)
		if rename_err != OK:
			completed_callback.call(false, "Failed to place update.pck into user directory")
			return
			
		# Step 3: Record update metadata for reboot verification
		var meta_data = {
			"version": target_version,
			"sha256": expected_sha256,
			"signature": signature_b64,
			"installed_at": Time.get_datetime_string_from_system()
		}
		var meta_file = FileAccess.open(UPDATE_META_PATH, FileAccess.WRITE)
		if meta_file:
			meta_file.store_string(JSON.stringify(meta_data, "  "))
			meta_file.close()
			
		# Step 4: Dynamically mount resource pack
		var success = ProjectSettings.load_resource_pack(UPDATE_PCK_PATH, true)
		if success:
			active_version = target_version
			print("[Updater] Successfully loaded signed resource pack: v", active_version)
			completed_callback.call(true, "Updated successfully to v" + target_version)
		else:
			completed_callback.call(false, "Failed to mount .pck resource pack")
	)
	
	var err = http.request(download_url)
	if err != OK:
		http.queue_free()
		completed_callback.call(false, "Could not start download request")

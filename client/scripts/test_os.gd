extends SceneTree
func _init():
	var reader = ZIPReader.new()
	print("ZIPReader exists: ", reader != null)
	quit()

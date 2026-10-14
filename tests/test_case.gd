extends RefCounted
## Base class for test files. The runner sets `tree` and a fresh `world` before each test method.

var tree: SceneTree
var world: Node2D
var failures: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


## Coroutine: wait `n` physics frames.
func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Instantiate `path`, set `props` before entering the tree, add it to `world` at `pos`.
func spawn(path: String, pos: Vector2, props: Dictionary = {}) -> Node:
	var node: Node = load(path).instantiate()
	for key in props:
		node.set(key, props[key])
	node.position = pos
	world.add_child(node)
	return node

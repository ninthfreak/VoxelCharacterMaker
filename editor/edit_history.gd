@tool
class_name EditHistory
extends RefCounted

## Undo/redo for every edit (SPEC.md section 8), by snapshot.
##
## The documents being edited here are small -- a wardrobe is a few kilobytes
## of JSON, a body is a few thousand cells -- so a snapshot per edit costs
## almost nothing and cannot drift out of sync with the model the way a command
## stack can. Every edit path therefore goes through one call:
##
##   history.commit("Set bulk on upper chest", wardrobe.to_json())
##
## taken AFTER the change is applied. The entry before it is what undo restores.
##
## This class knows nothing about what a snapshot contains. The wardrobe stores
## its JSON here and the body editor stores its cells; each caller turns what
## comes back into its own model again. That is what lets one undo stack serve
## both without either knowing about the other.

const MAX_ENTRIES := 200

signal changed

class Entry extends RefCounted:
	var label: String
	var data: Dictionary

	func _init(p_label: String, p_data: Dictionary) -> void:
		label = p_label
		data = p_data

## Array of Entry. Untyped on purpose: a typed array of an inner class is
## fragile in GDScript.
var _entries: Array = []
var _at: int = -1


## Record the starting state. Call once, with the freshly loaded document.
func reset(data: Dictionary, label: String = "Opened") -> void:
	_entries.clear()
	_at = -1
	_entries.append(Entry.new(label, data.duplicate(true)))
	_at = 0
	changed.emit()


## Record the state after an edit.
func commit(label: String, data: Dictionary) -> void:
	# Drop anything that was undone: a new edit replaces that future.
	while _entries.size() > _at + 1:
		_entries.remove_at(_entries.size() - 1)
	_entries.append(Entry.new(label, data.duplicate(true)))
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_at = _entries.size() - 1
	changed.emit()


func can_undo() -> bool:
	return _at > 0


func can_redo() -> bool:
	return _at >= 0 and _at < _entries.size() - 1


## Step back and return the snapshot to restore, or {} when there is none.
func undo() -> Dictionary:
	if not can_undo():
		return {}
	_at -= 1
	changed.emit()
	return _snapshot_at(_at)


func redo() -> Dictionary:
	if not can_redo():
		return {}
	_at += 1
	changed.emit()
	return _snapshot_at(_at)


## The state as it currently stands, for a caller that needs to re-read it.
func current() -> Dictionary:
	if _at < 0:
		return {}
	return _snapshot_at(_at)


func _snapshot_at(index: int) -> Dictionary:
	return (_entries[index] as Entry).data.duplicate(true)


func is_empty() -> bool:
	return _entries.is_empty()


## What undo would reverse, for the menu label. Kept short and plain.
func undo_label() -> String:
	if not can_undo():
		return ""
	return (_entries[_at] as Entry).label


func redo_label() -> String:
	if not can_redo():
		return ""
	return (_entries[_at + 1] as Entry).label


func depth() -> int:
	return _entries.size()

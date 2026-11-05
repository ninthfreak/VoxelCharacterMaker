@tool
class_name EditHistory
extends RefCounted

## Undo/redo for every edit (SPEC.md section 8), by snapshot.
##
## The wardrobe is a small JSON document -- a few kilobytes -- so a snapshot per
## edit costs almost nothing and cannot drift out of sync with the model the way
## a command stack can. Every edit path therefore goes through one call:
##
##   history.commit("Set bulk on upper chest", wardrobe)
##
## taken AFTER the change is applied. The entry before it is what undo restores.

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


## Record the starting state. Call once, with the freshly loaded wardrobe.
func reset(wardrobe: Wardrobe, label: String = "Opened") -> void:
	_entries.clear()
	_at = -1
	if wardrobe != null:
		_entries.append(Entry.new(label, wardrobe.to_json()))
		_at = 0
	changed.emit()


## Record the state after an edit.
func commit(label: String, wardrobe: Wardrobe) -> void:
	if wardrobe == null:
		return
	# Drop anything that was undone: a new edit replaces that future.
	while _entries.size() > _at + 1:
		_entries.remove_at(_entries.size() - 1)
	_entries.append(Entry.new(label, wardrobe.to_json()))
	if _entries.size() > MAX_ENTRIES:
		_entries.remove_at(0)
	_at = _entries.size() - 1
	changed.emit()


func can_undo() -> bool:
	return _at > 0


func can_redo() -> bool:
	return _at >= 0 and _at < _entries.size() - 1


## Step back and return the wardrobe to restore, or null.
func undo() -> Wardrobe:
	if not can_undo():
		return null
	_at -= 1
	changed.emit()
	return _restore(_at)


func redo() -> Wardrobe:
	if not can_redo():
		return null
	_at += 1
	changed.emit()
	return _restore(_at)


func _restore(index: int) -> Wardrobe:
	return Wardrobe.from_json((_entries[index] as Entry).data.duplicate(true))


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

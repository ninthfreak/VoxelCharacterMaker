@tool
class_name ItemSelection
extends RefCounted

## Which item a group of panels is working on, and in which colourway.
##
## The Clothes tab has one of these for clothing; the Face & Hair tab has one
## for hair and one for facial hair. Panels take a selection instead of asking
## the editor for "the" selected item, so the same garment and colour panels
## can edit a hat in one tab and a beard in another without their selections
## getting mixed up.

signal changed

var editor: CharacterEditor = null
## "" for clothing, else the feature slot.
var slot: String = GarmentItem.CLOTHES
var item_id: String = ""
## The colourway being looked at, for the preview and the colour panel.
var colourway: String = ""


static func make(p_editor: CharacterEditor, p_slot: String) -> ItemSelection:
	var s := ItemSelection.new()
	s.editor = p_editor
	s.slot = p_slot
	return s


func item() -> GarmentItem:
	if editor == null or editor.wardrobe == null or item_id.is_empty():
		return null
	var it := editor.wardrobe.item(item_id)
	# A selection never points across sections: an id that is now some other
	# slot's (after an undo, say) is no selection at all.
	if it == null or it.slot != slot:
		return null
	return it


func select(p_item_id: String) -> void:
	var it := editor.wardrobe.item(p_item_id) if editor != null and editor.wardrobe != null \
		and not p_item_id.is_empty() else null
	var next_colourway := colourway
	if it == null:
		next_colourway = ""
	elif not it.has_colourway(next_colourway):
		next_colourway = it.first_colourway()
	if p_item_id == item_id and next_colourway == colourway:
		return
	item_id = p_item_id
	colourway = next_colourway
	changed.emit()


func set_colourway(p_colourway: String) -> void:
	if p_colourway == colourway:
		return
	colourway = p_colourway
	changed.emit()


## Drop a selection whose item has gone, or fix a colourway that has. Returns
## true if anything changed.
func validate() -> bool:
	var it := item()
	if it == null:
		if item_id.is_empty():
			return false
		item_id = ""
		colourway = ""
		changed.emit()
		return true
	if not it.has_colourway(colourway):
		colourway = it.first_colourway()
		changed.emit()
		return true
	return false


## For the assembler: the selected item as a worn entry, or none.
func as_worn() -> Array:
	var it := item()
	if it == null:
		return []
	return [{"item": it.id, "colourway": colourway if it.has_colourway(colourway)
		else it.first_colourway()}]

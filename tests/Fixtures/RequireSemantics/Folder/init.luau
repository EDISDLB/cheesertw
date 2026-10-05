-- Fixture: folder module. "@self/X" = child of Folder; "./X" = sibling of Folder; "../X" = sibling of the parent.
return {
	name = "Folder",
	child = require("@self/Child"),
	sibling = require("./Leaf"),
	viaParent = require("../RequireSemantics/Leaf"),
}

-- Fixture: "../X" from a module inside Folder resolves to a sibling of Folder.
return { name = "Child", up = require("../Leaf") }

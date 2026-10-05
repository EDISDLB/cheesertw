-- Fixture: "../../X" from a regular module two folders deep; "./X" is a sibling inside the same folder.
return { name = "UpTwo", leaf = require("../../Leaf"), inner = require("./Inner") }

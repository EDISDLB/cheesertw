-- Fixture: "./X" from a regular module resolves to a sibling file.
return { name = "Sibling", leaf = require("./Leaf") }

-- Fixture: nested folder module; "./Child" is Folder/Child (a sibling of Deep).
return { name = "Deep", inner = require("@self/Inner"), sibling = require("./Child") }

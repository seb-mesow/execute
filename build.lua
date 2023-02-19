module = "execute"

maindir = maindir or "."

stdengine = "luatex"
checkengines = { "luatex" }
checkformat = "tex"

-- misuse of testsuppdir
testsuppdir = maindir.."/source"
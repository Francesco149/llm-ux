-- testmain.lua — Headless test runner
require("test_lua54_compat")
require("test_binding_parity")
require("test_mesh")
require("test_ui_smoke")
print("\nAll test suites passed.")
os.exit(0)

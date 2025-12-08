local map = vim.keymap.set

map("n", "<leader>fr", "<cmd>FlutterReload<CR>", { desc = "Flutter Hot Reload" })
map("n", "<leader>fR", "<cmd>FlutterRestart<CR>", { desc = "Flutter Hot Restart" })
map("n", "<leader>fd", "<cmd>FlutterDevices<CR>", { desc = "Flutter Devices" })
map("n", "<leader>fe", "<cmd>FlutterEmulators<CR>", { desc = "Flutter Emulators" })
map("n", "<leader>fo", "<cmd>FlutterOutlineToggle<CR>", { desc = "Flutter Outline" })
map("n", "<leader>fq", "<cmd>FlutterQuit<CR>", { desc = "Quit Flutter" })

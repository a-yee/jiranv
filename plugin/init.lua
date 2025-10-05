local core = require("jiranv")

-- Open the project selector from cmd mode
vim.api.nvim_create_user_command("JiraProjects", core.JiraProjects, {
	nargs = 0,
	desc = "Show list of jira projects available",
})

-- Allow user to set the project directly from cmd mode without Telescope
vim.api.nvim_create_user_command("JiraProject", core.JiraProject, {
	nargs = 1,
	desc = "Set the active jira project",
})

-- 1. Create a unique augroup for your plugin's autocmds
local my_plugin_augroup = vim.api.nvim_create_augroup("MyJiraPluginOptions", { clear = true })

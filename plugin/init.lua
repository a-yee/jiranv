local core = require("jiranv")

vim.api.nvim_create_user_command("JiraProjects", core.JiraProject, {
	nargs = 0,
	desc = "Show list of jira projects available",
})

local M = {}

-- Stores the user configuration and state
M.config = {
	project_key = nil,
	default_project_key = nil,
	-- New configuration to store user's known project keys
	project_keys = {},
}

-- Check if project is set and notify if not
local function check_project_key()
	if not M.config.project_key then
		vim.notify(
			"Jira project key is not set. Use :JiraProject to select one.",
			vim.log.levels.WARN,
			{ title = "Jira Plugin" }
		)
		return false
	end
	return true
end

-- Utility function to execute the jira-cli command
-- @param command_name (string): e.g., 'issue' or 'project'
-- @param args (table): array of strings for command arguments
-- @param required_project (boolean): if true, checks M.config.project_key before running
local function exec_jira(command_name, args, required_project)
	if required_project and not check_project_key() then
		return nil
	end

	-- Fix for Lua 5.2+ compatibility: using table.unpack instead of global unpack
	local cmd = vim.tbl_flatten({ "jira", command_name, table.unpack(args) })

	vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, event)
			-- For debugging: print(vim.inspect(data))
		end,
		on_stderr = function(_, data, event)
			if #data > 0 then
				vim.notify(
					"Jira CLI Error: " .. table.concat(data, " "),
					vim.log.levels.ERROR,
					{ title = "Jira Plugin" }
				)
			end
		end,
		stdout_buffered = true,
		-- The jira-cli often outputs to stderr for help/status, but we only care about real errors.
	})
end

-- =============================================================================
-- Internal Helpers (Telescope)
-- =============================================================================

local function picker_action_default(prompt_bufnr)
	local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
	local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)

	if not selection or not selection.key then
		return
	end

	-- Default action: open issue in browser (using 'jira issue view <KEY>')
	exec_jira("issue", { "view", selection.key }, false)

	require("telescope.actions").close(prompt_bufnr)
end

local function picker_action_comment(prompt_bufnr)
	local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
	local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)

	if not selection or not selection.key then
		return
	end

	require("telescope.actions").close(prompt_bufnr)

	-- Request the comment text from the user
	M.add_comment(selection.key)
end

-- =============================================================================
-- Public API Functions
-- =============================================================================

-- Add a comment to a specified issue key
M.add_comment = function(issue_key)
	local comment_text = vim.fn.input("Enter comment for " .. issue_key .. ": ")

	if comment_text and comment_text ~= "" then
		-- Execute the comment command
		exec_jira("issue", { "comment", issue_key, "-m", comment_text }, false)
		vim.notify("Comment added to " .. issue_key, vim.log.levels.INFO, { title = "Jira Plugin" })
	else
		vim.notify("Comment cancelled or empty.", vim.log.levels.INFO, { title = "Jira Plugin" })
	end
end

M.pickers = {}

-- Project selector picker (Bound to :JiraProject)
M.pickers.project_selector = function()
	local keys = M.config.project_keys
	vim.notify(string.format("%s", vim.inspect(M.config)))

	if not keys or vim.tbl_isempty(keys) then
		vim.notify(
			'No project keys defined. Set the "project_keys" option in your setup.',
			vim.log.levels.ERROR,
			{ title = "Jira Plugin" }
		)
		return
	end

	local project_entries = {}
	for _, key in ipairs(keys) do
		-- Use the key as both the internal value and the display name
		table.insert(project_entries, {
			key = key,
			value = key,
			display = key,
		})
	end

	require("telescope.pickers")
		.new({}, {
			prompt_title = "Jira Project Selector",
			finder = require("telescope.finders").new_table({ results = project_entries }),
			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr)
				require("telescope.actions").select_default:enhance({
					callback = function()
						local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
						if selection and selection.key then
							M.config.project_key = selection.key
							vim.notify(
								"Active Jira project set to: " .. selection.key,
								vim.log.levels.INFO,
								{ title = "Jira Plugin" }
							)
						end
						require("telescope.actions").close(prompt_bufnr)
					end,
				})
				return true
			end,
		})
		:find()
end

-- Issue list picker (Bound to :JiraOpenIssues)
M.pickers.open_issues = function()
	if not check_project_key() then
		return
	end

	-- Fetch open issues for the configured project key
	local cmd = string.format("jira issue list --project %s --status Open --plain", M.config.project_key)
	local results = vim.fn.systemlist(cmd)

	local issue_entries = {}
	for _, line in ipairs(results) do
		-- Assuming format: <KEY> <SUMMARY> (<STATUS>)
		local key = line:match("^%S+")
		if key then
			table.insert(issue_entries, {
				key = key,
				value = line,
				display = line,
			})
		end
	end

	require("telescope.pickers")
		.new({}, {
			prompt_title = "Open Issues (" .. M.config.project_key .. ")",
			finder = require("telescope.finders").new_table({ results = issue_entries }),
			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr)
				local actions = require("telescope.actions")

				-- Default action: open in browser
				actions.select_default:enhance({
					callback = function()
						picker_action_default(prompt_bufnr)
					end,
				})

				-- Custom mapping: Add comment (Ctrl-c)
				actions.new({ i = { ["<C-c>"] = picker_action_comment } })(prompt_bufnr)

				return true
			end,
		})
		:find()
end

-- New function bound to :JiraProject command
M.JiraProject = M.pickers.project_selector

-- Setup function (called by lazy.nvim)
M.setup = function(opts)
	opts = opts or {}

	-- Store mandatory list of project keys
	if opts.project_keys and type(opts.project_keys) == "table" then
		M.config.project_keys = opts.project_keys
	end

	-- Prioritize 'project_key' if present, otherwise fall back to 'default_project_key'
	if opts.project_key then
		M.config.project_key = opts.project_key
	elseif opts.default_project_key then
		M.config.project_key = opts.default_project_key
	end
end

return M

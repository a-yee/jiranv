local M = {}

local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers_module = require("telescope.pickers")
local previewers = require("telescope.previewers")

-- Stores the user configuration and state
-- project_key = plugin will use this project for each command
-- default_project_key = init state of project_key on startup if set cfg
-- project_keys = list of jira projects the plugin can interact with
M.config = {
	project_key = nil,
	default_project_key = nil,
	project_keys = {},
}

-- Check if project is set and notify if not
local function check_project_key()
	if not M.config.project_key then
		vim.notify(
			"Jira project key is not set. Use :JiraProjects to select one.",
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
	local picker = action_state.get_current_picker(prompt_bufnr)
	local selection = action_state.get_selected_entry(prompt_bufnr)

	if not selection or not selection.key then
		return
	end

	-- Default action: open issue in browser (using 'jira issue view <KEY>')
	exec_jira("issue", { "view", selection.key }, false)

	require("telescope.actions").close(prompt_bufnr)
end

local function picker_action_comment(prompt_bufnr)
	local picker = action_state.get_current_picker(prompt_bufnr)
	local selection = action_state.get_selected_entry(prompt_bufnr)

	if not selection or not selection.key then
		return
	end

	require("telescope.actions").close(prompt_bufnr)

	-- Request the comment text from the user
	M.add_comment(selection.key)
end

-- @param issue_json table decoded json from jira issue --raw
local function parse_issue_info(issue_json)
	-- TODO: figure out a way to conceal the header syntax
	local issue_info = {
		string.format("# %s", issue_json.key),
		"",
		"## SUMMARY",
		issue_json.fields.summary,
		"",
		"## DESCRIPTION", -- TODO: need to figure out how to destructure this
		string.format("%s", issue_json.fields.description),
	}
	return issue_info
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

-- Project setter (Bound to :JiraProject <project_key>)
local function set_project_key(opts)
	local project_key = opts.args
	M.config.project_key = project_key
end

M.JiraProject = set_project_key

M.pickers = {}

-- Project selector picker (Bound to :JiraProjects)
M.pickers.project_selector = function()
	if #M.config.project_keys == 0 then
		vim.notify("No project keys defined. Please configure 'project_keys' in setup.", vim.log.levels.ERROR)
		return
	end

	local picker_finder = finders.new_table({
		results = M.config.project_keys,
		entry_maker = function(key)
			return {
				value = key,
				display = key .. (key == M.config.project_key and " (Active)" or ""),
				ordinal = key,
			}
		end,
	})

	-- Use pickers_module.new and pass the finder inside the options table
	pickers_module
		.new({
			prompt_title = "Jira Project Selector",
			default_selection_on_kbd_input = false,
			finder = picker_finder,
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				-- Map the Enter key to select the project
				map("i", "<CR>", function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection and selection.value then
						M.config.project_key = selection.value
						-- TODO: this disappears immediately, have it render longer
						vim.notify("Jira project set to: " .. selection.value, vim.log.levels.INFO)
					end
				end)
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
	-- TODO: for now use hardcoded status filters, in the future, make this dynamic
	-- from user configs
	-- TODO: make the whole function parametrizable, should also consider done or narrower scope
	local cmd = string.format(
		"jira issue list --project %s --status 'TO DO' --status 'IN PROGRESS' --plain --columns KEY,SUMMARY,STATUS --no-headers",
		M.config.project_key
	)
	local output = vim.fn.systemlist(cmd)

	local issues = {}
	for i = 1, #output do
		local line = output[i]
		if line:match("^[%s]*%w+%-") then -- Basic check for JIRA key pattern
			-- split on [\t+], get non-tab parts
			local parts = {}
			for part in line:gmatch("([^\t]+)") do
				table.insert(parts, part)
			end
			if #parts >= 2 then
				-- TODO: rework this section with a configuration of headers/pos
				-- using this you can create custom layout for the output here
				local key = parts[1]:match("([%w%d%-%s]+)")
				local summary = parts[2]:match("^%s*(.*%S)%s*$") -- Get trimmed summary

				if key and summary then
					table.insert(issues, {
						key = key:match("^%s*(.*%S)%s*$"), -- Final trim
						summary = summary,
						-- TODO: make the table fixed length and truncate summary as needed
						display = string.format("[%s] %s", key, summary),
						ordinal = key .. " " .. summary,
					})
				end
			end
		end
	end

	if #issues == 0 then
		vim.notify("No Open issues found for project " .. M.config.project_key, vim.log.levels.INFO)
		return
	end

	local picker_finder = finders.new_table({
		results = issues,
		entry_maker = function(issue)
			return {
				value = issue.key,
				display = issue.display,
				ordinal = issue.ordinal,
			}
		end,
	})

	-- Use pickers_module.new and pass the finder inside the options table
	pickers_module
		.new({
			prompt_title = M.config.project_key .. " Open Issues",
			finder = picker_finder,
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				map("i", "<CR>", function()
					local entry = action_state.get_selected_entry()
					if entry and entry.value then
						local cmd = string.format(
							"jira issue view --project %s --plain --comments 5 %s --raw",
							M.config.project_key,
							entry.value
						)
						local output = vim.fn.system(cmd)
						local issue_data, error_msg = vim.json.decode(output)
						if error_msg then
							vim.notify(string.format("Error getting info for %s: %s", entry.value, error_msg))
							return
						end
						-- TODO: write helper function which parses the json then constructs nice output for preview
						-- vim.notify(vim.inspect(issue_data))
						local issue_info = parse_issue_info(issue_data)

						local picker = action_state.get_current_picker(prompt_bufnr)
						local previewer_state = picker.previewer.state
						local preview_bufnr = previewer_state.bufnr
						-- Check if the buffer is valid before attempting to write
						if vim.api.nvim_buf_is_valid(preview_bufnr) then
							vim.api.nvim_buf_set_lines(
								preview_bufnr, -- The target buffer ID
								0, -- Start line (0 for beginning)
								-1, -- End line (-1 for end)
								false, -- Strict indexing
								issue_info -- The new content (table of strings)
							)
							-- required to wrap long lines
							vim.api.nvim_buf_set_option(preview_bufnr, "wrap", true)
							vim.api.nvim_buf_set_option(preview_bufnr, "linebreak", true)
						end
					end
				end)

				---- Custom action: Add Comment
				--map("i", "<C-c>", function()
				--	local entry = action_state.get_selected_entry()
				--	actions.close(prompt_bufnr)
				--	if entry and entry.value then
				--		M.add_comment(entry.value)
				--	end
				--end)
				return true
			end,
			previewer = previewers.new_buffer_previewer({
				hidden = true,
				define_preview = function(self, entry)
					if not entry or not entry.value then
						-- Clear the buffer if the entry is invalid or missing data
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No entry data available." })
						return
					end

					vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "markdown")
				end,
			}),
		})
		:find()
end

-- New function bound to :JiraProject command
M.JiraProjects = M.pickers.project_selector

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

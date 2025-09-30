--local M = {}
--
---- Stores the user configuration and state
--M.config = {
--	project_key = nil,
--	default_project_key = nil,
--	-- New configuration to store user's known project keys
--	project_keys = {},
--}
--
---- Check if project is set and notify if not
--local function check_project_key()
--	if not M.config.project_key then
--		vim.notify(
--			"Jira project key is not set. Use :JiraProject to select one.",
--			vim.log.levels.WARN,
--			{ title = "Jira Plugin" }
--		)
--		return false
--	end
--	return true
--end
--
---- Utility function to execute the jira-cli command
---- @param command_name (string): e.g., 'issue' or 'project'
---- @param args (table): array of strings for command arguments
---- @param required_project (boolean): if true, checks M.config.project_key before running
--local function exec_jira(command_name, args, required_project)
--	if required_project and not check_project_key() then
--		return nil
--	end
--
--	-- Fix for Lua 5.2+ compatibility: using table.unpack instead of global unpack
--	local cmd = vim.tbl_flatten({ "jira", command_name, table.unpack(args) })
--
--	vim.fn.jobstart(cmd, {
--		on_stdout = function(_, data, event)
--			-- For debugging: print(vim.inspect(data))
--		end,
--		on_stderr = function(_, data, event)
--			if #data > 0 then
--				vim.notify(
--					"Jira CLI Error: " .. table.concat(data, " "),
--					vim.log.levels.ERROR,
--					{ title = "Jira Plugin" }
--				)
--			end
--		end,
--		stdout_buffered = true,
--		-- The jira-cli often outputs to stderr for help/status, but we only care about real errors.
--	})
--end
--
---- =============================================================================
---- Internal Helpers (Telescope)
---- =============================================================================
--
--local function picker_action_default(prompt_bufnr)
--	local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
--	local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
--
--	if not selection or not selection.key then
--		return
--	end
--
--	-- Default action: open issue in browser (using 'jira issue view <KEY>')
--	exec_jira("issue", { "view", selection.key }, false)
--
--	require("telescope.actions").close(prompt_bufnr)
--end
--
--local function picker_action_comment(prompt_bufnr)
--	local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
--	local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
--
--	if not selection or not selection.key then
--		return
--	end
--
--	require("telescope.actions").close(prompt_bufnr)
--
--	-- Request the comment text from the user
--	M.add_comment(selection.key)
--end
--
---- =============================================================================
---- Public API Functions
---- =============================================================================
--
---- Add a comment to a specified issue key
--M.add_comment = function(issue_key)
--	local comment_text = vim.fn.input("Enter comment for " .. issue_key .. ": ")
--
--	if comment_text and comment_text ~= "" then
--		-- Execute the comment command
--		exec_jira("issue", { "comment", issue_key, "-m", comment_text }, false)
--		vim.notify("Comment added to " .. issue_key, vim.log.levels.INFO, { title = "Jira Plugin" })
--	else
--		vim.notify("Comment cancelled or empty.", vim.log.levels.INFO, { title = "Jira Plugin" })
--	end
--end
--
--M.pickers = {}
--
---- Project selector picker (Bound to :JiraProject)
--M.pickers.project_selector = function()
--	local keys = M.config.project_keys
--
--	if not keys or vim.tbl_isempty(keys) then
--		vim.notify(
--			'No project keys defined. Set the "project_keys" option in your setup.',
--			vim.log.levels.ERROR,
--			{ title = "Jira Plugin" }
--		)
--		return
--	end
--
--	local project_entries = {}
--	for _, key in ipairs(keys) do
--		-- Use the key as both the internal value and the display name
--		table.insert(project_entries, {
--			key = key,
--			value = key,
--			display = key,
--		})
--	end
--
--	require("telescope.pickers")
--		.new({}, {
--			prompt_title = "Jira Project Selector",
--			finder = require("telescope.finders").new_table({ results = project_entries }),
--			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
--			attach_mappings = function(prompt_bufnr)
--				require("telescope.actions").select_default:enhance({
--					callback = function()
--						local selection = require("telescope.actions.state").get_selected_entry(prompt_bufnr)
--						if selection and selection.key then
--							M.config.project_key = selection.key
--							vim.notify(
--								"Active Jira project set to: " .. selection.key,
--								vim.log.levels.INFO,
--								{ title = "Jira Plugin" }
--							)
--						end
--						require("telescope.actions").close(prompt_bufnr)
--					end,
--				})
--				return true
--			end,
--		})
--		:find()
--end
--
---- Issue list picker (Bound to :JiraOpenIssues)
--M.pickers.open_issues = function()
--	if not check_project_key() then
--		return
--	end
--
--	-- Fetch open issues for the configured project key
--	local cmd = string.format("jira issue list --project %s --status Open --plain", M.config.project_key)
--	local results = vim.fn.systemlist(cmd)
--
--	local issue_entries = {}
--	for _, line in ipairs(results) do
--		-- Assuming format: <KEY> <SUMMARY> (<STATUS>)
--		local key = line:match("^%S+")
--		if key then
--			table.insert(issue_entries, {
--				key = key,
--				value = line,
--				display = line,
--			})
--		end
--	end
--
--	require("telescope.pickers")
--		.new({}, {
--			prompt_title = "Open Issues (" .. M.config.project_key .. ")",
--			finder = require("telescope.finders").new_table({ results = issue_entries }),
--			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
--			attach_mappings = function(prompt_bufnr)
--				local actions = require("telescope.actions")
--
--				-- Default action: open in browser
--				actions.select_default:enhance({
--					callback = function()
--						picker_action_default(prompt_bufnr)
--					end,
--				})
--
--				-- Custom mapping: Add comment (Ctrl-c)
--				actions.new({ i = { ["<C-c>"] = picker_action_comment } })(prompt_bufnr)
--
--				return true
--			end,
--		})
--		:find()
--end
--
---- New function bound to :JiraProject command
--M.JiraProject = M.pickers.project_selector
--
---- Setup function (called by lazy.nvim)
--M.setup = function(opts)
--	opts = opts or {}
--
--	-- Store mandatory list of project keys
--	if opts.project_keys and type(opts.project_keys) == "table" then
--		M.config.project_keys = opts.project_keys
--	end
--
--	-- Prioritize 'project_key' if present, otherwise fall back to 'default_project_key'
--	if opts.project_key then
--		M.config.project_key = opts.project_key
--	elseif opts.default_project_key then
--		M.config.project_key = opts.default_project_key
--	end
--end
--
--return M

local M = {}

--- Internal configuration store
M.config = {
	-- Placeholder/default config, overwritten by setup()
	project_keys = {},
	default_project_key = nil,
	active_project_key = nil,
}

--- @param opts table Configuration options passed from lazy.nvim
M.setup = function(opts)
	opts = opts or {}
	-- Merge defaults with user options
	M.config.project_keys = opts.project_keys or {}
	M.config.default_project_key = opts.default_project_key
	M.config.active_project_key = opts.project_key or opts.default_project_key

	if #M.config.project_keys == 0 then
		-- This check is necessary as project_keys must be defined for :JiraProject to work
		vim.notify(
			"Jira CLI Plugin: No project keys defined. Set the 'project_keys' option in your setup.",
			vim.log.levels.WARN
		)
	end
end

--- Executes the jira-cli command and returns the stdout lines.
--- @param args string[] Command arguments to pass to jira-cli (e.g., {'issue', 'list'})
--- @param allow_no_project boolean If true, command runs even if no project is active (e.g., for project selector)
--- @return string[]|nil Lines of stdout output, or nil on failure/no output.
local function exec_jira(args, allow_no_project)
	if not allow_no_project and not M.config.active_project_key then
		vim.notify("No active Jira project set. Use :JiraProject to select one.", vim.log.levels.WARN)
		return nil
	end

	local final_args = vim.deepcopy(args)

	-- If a project is active and required, prepend it to the issue list command
	if M.config.active_project_key and final_args[1] == "issue" and final_args[2] == "list" then
		table.insert(final_args, 3, "--project")
		table.insert(final_args, 4, M.config.active_project_key)
	end

	-- Mandatory plain output for parsing
	table.insert(final_args, "--plain")

	local full_command = { "jira" }
	for _, arg in ipairs(final_args) do
		table.insert(full_command, arg)
	end

	-- NOTE: table.unpack is used instead of unpack for Lua 5.2+ compatibility
	-- local full_command = {'jira', table.unpack(final_args)}

	local job = vim.fn.jobstart(full_command, {
		stdout_buffered = true,
		-- using default timeout of 1000ms (1 second)
	})

	-- Wait for the job to finish
	vim.fn.jobwait({ job }, 1000)

	local stdout = vim.split(vim.fn.jobget(job), "\n", {})
	local status = vim.fn.jobreturn(job)

	-- --- DEBUGGING ---
	if status ~= 0 or #stdout < 2 then -- Check if status is error or output is virtually empty (header/empty lines)
		local command_string = table.concat(full_command, " ")

		vim.notify(
			string.format("Jira CLI Error (Status: %d). Check ':messages' for details.", status),
			vim.log.levels.ERROR
		)
		vim.print("--- JIRA CLI DEBUG ---")
		vim.print("Command: " .. command_string)
		vim.print("Status Code: " .. status)
		vim.print("Raw Output:", vim.inspect(stdout))
		vim.print("----------------------")
		return nil -- Return nil on error
	end
	-- --- END DEBUGGING ---

	return stdout
end

--- Telescope Integration
M.pickers = {}

--- Opens a Telescope picker for the list of configured projects
M.pickers.project_selector = function()
	if #M.config.project_keys == 0 then
		vim.notify("No project keys defined. Please configure 'project_keys' in setup.", vim.log.levels.ERROR)
		return
	end

	local picker = require("telescope.finders").new_table({
		results = M.config.project_keys,
		entry_maker = function(key)
			return {
				value = key,
				display = key .. (key == M.config.active_project_key and " (Active)" or ""),
				ordinal = key,
			}
		end,
	})

	require("telescope.ui.picker")
		.create(picker, {
			prompt_title = "Jira Project Selector",
			default_selection_on_kbd_input = false,
			finder = picker,
			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				-- Map the Enter key to select the project
				map("i", "<CR>", function()
					local entry = require("telescope.actions").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)
					if entry and entry.value then
						M.config.active_project_key = entry.value
						vim.notify("Jira project set to: " .. entry.value, vim.log.levels.INFO)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Opens a Telescope picker for open issues in the active project
M.pickers.open_issues = function()
	local output = exec_jira({ "issue", "list", "--status", "Open" })
	if not output then
		return
	end

	local issues = {}
	-- Skip the header line (output[1] is the header)
	for i = 2, #output do
		local line = output[i]
		if line:match("^[%s]*%w+%-") then -- Basic check for JIRA key pattern
			local parts = vim.split(line, "|", { plain = true, trimempty = true })
			if #parts >= 3 then
				local key = parts[1]:match("([%w%d%-%s]+)")
				local summary = parts[3]:match("^%s*(.*%S)%s*$") -- Get trimmed summary

				if key and summary then
					table.insert(issues, {
						key = key:match("^%s*(.*%S)%s*$"), -- Final trim
						summary = summary,
						display = string.format("[%s] %s", key, summary),
						ordinal = key .. " " .. summary,
					})
				end
			end
		end
	end

	if #issues == 0 then
		vim.notify("No Open issues found for project " .. M.config.active_project_key, vim.log.levels.INFO)
		return
	end

	local picker = require("telescope.finders").new_table({
		results = issues,
		entry_maker = function(issue)
			return {
				value = issue.key,
				display = issue.display,
				ordinal = issue.ordinal,
			}
		end,
	})

	require("telescope.ui.picker")
		.create(picker, {
			prompt_title = M.config.active_project_key .. " Open Issues",
			finder = picker,
			sorter = require("telescope.sorters").get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				-- Default action: Open issue URL (relying on 'jira issue view' behavior)
				map("i", "<CR>", function()
					local entry = require("telescope.actions").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)
					if entry and entry.value then
						exec_jira({ "issue", "view", entry.value })
					end
				end)

				-- Custom action: Add Comment
				map("i", "<C-c>", function()
					local entry = require("telescope.actions").get_selected_entry()
					require("telescope.actions").close(prompt_bufnr)
					if entry and entry.value then
						M.add_comment(entry.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Public functions
M.JiraProject = M.pickers.project_selector

--- Prompts user for a comment and submits it to the given issue key.
--- @param issue_key string The key of the issue (e.g., "PROJ-123")
M.add_comment = function(issue_key)
	vim.notify("Adding comment to " .. issue_key .. "...", vim.log.levels.INFO)

	-- Use vim.fn.input() to get a single line comment quickly
	local comment_text = vim.fn.input("Comment for " .. issue_key .. ": ")

	if comment_text == nil or comment_text == "" then
		vim.notify("Comment cancelled.", vim.log.levels.INFO)
		return
	end

	-- Run the command to add the comment
	local output = exec_jira({ "issue", "comment", issue_key, "-m", comment_text })

	if output then
		vim.notify("Comment successfully added to " .. issue_key, vim.log.levels.INFO)
	else
		vim.notify("Failed to add comment to " .. issue_key .. ". Check :messages.", vim.log.levels.ERROR)
	end
end

return M

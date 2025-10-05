local M = {}

local function adf_to_markdown(node)
	local output = ""

	-- If the node is just a string (simple text content), return it.
	if type(node) == "string" then
		return node
	end

	-- If the node is a list of children, recursively process them.
	if type(node) == "table" and node.content then
		for _, child in ipairs(node.content) do
			output = output .. adf_to_markdown(child)
		end
	end

	-- Process the current node based on its type.
	if node.type == "paragraph" then
		-- Paragraphs should have a blank line after them in Markdown
		output = output .. "\n\n"
	elseif node.type == "heading" then
		local level = node.attrs and node.attrs.level or 1
		local hashes = string.rep("#", level)
		output = hashes .. " " .. output .. "\n"
	elseif node.type == "bulletList" then
		-- Handle bullet lists by iterating children (listItem)
		for _, item in ipairs(node.content) do
			-- Assuming listItem content is handled recursively
			output = output .. "* " .. adf_to_markdown(item) .. "\n"
		end
	elseif node.type == "text" then
		-- Handle inline text formatting (marks)
		local text = node.text
		if node.marks then
			for _, mark in ipairs(node.marks) do
				if mark.type == "strong" then
					text = "**" .. text .. "**" -- Bold
				elseif mark.type == "code" then
					text = "`" .. text .. "`" -- Monospace
					-- Add more marks here (e.g., 'em' for italics)
				end
			end
		end
		output = output .. text
	elseif node.type == "listItem" then
		-- No explicit formatting needed here, just return content
		-- The parent bulletList handler adds the '* ' prefix
		return output

		-- Add more complex types (codeBlock, blockquote, media, etc.) here
	end

	return output
end

-- Function to clean up extra blank lines before final output
local function format_markdown_output(markdown_string)
	local blocks = vim.split(markdown_string, "\n", {})
end

local function process_document_markdown(adf_doc)
	local output = {}
	for _, node in ipairs(adf_doc.content) do
		local node_lines = adf_to_markdown(node)

		---- Iterate over the returned lines and insert them individually.
		--for _, line in ipairs(node2) do
		--	table.insert(output, line)
		--end

		---- Add a spacing line between major blocks
		table.insert(output, node_lines)
	end

	return output
end

M.ToMd = process_document_markdown

return M

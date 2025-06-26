local api = vim.api
local config = require("competitest.config")
local utils = require("competitest.utils")

local M = {}

---Get the base filename without extension
---@param filepath string
---@return string, string # basename without extension, file extension
local function get_file_info(filepath)
	local filename = vim.fn.fnamemodify(filepath, ":t")
	local basename = vim.fn.fnamemodify(filename, ":r")
	local extension = vim.fn.fnamemodify(filename, ":e")
	return basename, extension
end

---Create template files for stress testing
---@param basename string base filename without extension
---@param extension string file extension
function M.setup()
	local current_file = api.nvim_buf_get_name(0)
	if current_file == "" then
		utils.notify("stress: no file is currently open", "ERROR")
		return
	end
	
	local basename, extension = get_file_info(current_file)
	local dir = vim.fn.fnamemodify(current_file, ":p:h")
	
	local gen_file = dir .. "/" .. basename .. "_gen." .. extension
	local brute_file = dir .. "/" .. basename .. "_brute." .. extension
	
	-- Create generator template
	local gen_template = ""
	if extension == "cpp" then
		gen_template = [[#include <iostream>
#include <random>
#include <ctime>
using namespace std;

int main() {
    // Initialize random seed
    srand(time(0));
    
    // Generate test data here
    // Example:
    int n = rand() % 10 + 1;  // Random n from 1 to 10
    cout << n << endl;
    
    for (int i = 0; i < n; i++) {
        int x = rand() % 100 + 1;  // Random number from 1 to 100
        cout << x << " ";
    }
    cout << endl;
    
    return 0;
}]]
	elseif extension == "py" then
		gen_template = [[import random
import sys

# Generate test data here
# Example:
n = random.randint(1, 10)
print(n)

for i in range(n):
    x = random.randint(1, 100)
    print(x, end=' ')
print()]]
	else
		gen_template = "// TODO: Implement data generator for " .. extension .. " files"
	end
	
	-- Create brute force template
	local brute_template = ""
	if extension == "cpp" then
		brute_template = [[#include <iostream>
using namespace std;

int main() {
    // TODO: Implement brute force solution here
    // This should be a simple, obviously correct solution
    // even if it's slow
    
    return 0;
}]]
	elseif extension == "py" then
		brute_template = [[# TODO: Implement brute force solution here
# This should be a simple, obviously correct solution
# even if it's slow

]]
	else
		brute_template = "// TODO: Implement brute force solution for " .. extension .. " files"
	end
	
	-- Write generator file
	if vim.fn.filereadable(gen_file) == 0 then
		local gen_f = io.open(gen_file, "w")
		if gen_f then
			gen_f:write(gen_template)
			gen_f:close()
			utils.notify("Created generator: " .. basename .. "_gen." .. extension, "INFO")
		else
			utils.notify("Failed to create generator file", "ERROR")
			return
		end
	else
		utils.notify("Generator file already exists: " .. basename .. "_gen." .. extension, "WARN")
	end
	
	-- Write brute force file  
	if vim.fn.filereadable(brute_file) == 0 then
		local brute_f = io.open(brute_file, "w")
		if brute_f then
			brute_f:write(brute_template)
			brute_f:close()
			utils.notify("Created brute force: " .. basename .. "_brute." .. extension, "INFO")
		else
			utils.notify("Failed to create brute force file", "ERROR")
			return
		end
	else
		utils.notify("Brute force file already exists: " .. basename .. "_brute." .. extension, "WARN")
	end
	
	-- Open files for editing
	vim.cmd("edit " .. gen_file)
	vim.cmd("vsplit " .. brute_file)
	
	utils.notify("Stress test files created! Edit them and run ':CompetiTest stress run'", "INFO")
end

---Clean up temporary stress test files
function M.clean()
	local current_file = api.nvim_buf_get_name(0)
	if current_file == "" then
		utils.notify("stress: no file is currently open", "ERROR")
		return
	end
	
	local basename, extension = get_file_info(current_file)
	local dir = vim.fn.fnamemodify(current_file, ":p:h")
	
	-- Clean up compiled files and temporary output
	local files_to_clean = {
		basename,
		basename .. "_gen",
		basename .. "_brute",
		"stress_input.txt",
		"stress_output_main.txt",
		"stress_output_brute.txt"
	}
	
	local cleaned = 0
	for _, file in ipairs(files_to_clean) do
		local filepath = dir .. "/" .. file
		if vim.fn.filereadable(filepath) == 1 then
			os.remove(filepath)
			cleaned = cleaned + 1
		end
	end
	
	utils.notify("Cleaned " .. cleaned .. " temporary files", "INFO")
end

---Run stress testing
function M.run()
	local current_file = api.nvim_buf_get_name(0)
	if current_file == "" then
		utils.notify("stress: no file is currently open", "ERROR")
		return
	end
	
	local basename, extension = get_file_info(current_file)
	local dir = vim.fn.fnamemodify(current_file, ":p:h")
	
	local main_file = current_file
	local gen_file = dir .. "/" .. basename .. "_gen." .. extension
	local brute_file = dir .. "/" .. basename .. "_brute." .. extension
	
	-- Check if required files exist
	if vim.fn.filereadable(gen_file) == 0 then
		utils.notify("Generator file not found: " .. basename .. "_gen." .. extension, "ERROR")
		utils.notify("Run ':CompetiTest stress setup' first", "INFO")
		return
	end
	
	if vim.fn.filereadable(brute_file) == 0 then
		utils.notify("Brute force file not found: " .. basename .. "_brute." .. extension, "ERROR")
		utils.notify("Run ':CompetiTest stress setup' first", "INFO")
		return
	end
	
	-- Save current file
	vim.cmd("write")
	
	-- Load configuration
	local bufnr = api.nvim_get_current_buf()
	config.load_buffer_config(bufnr)
	local bufcfg = config.get_buffer_config(bufnr)
	
	-- Get compile commands for the file type
	local compile_cmd = bufcfg.compile_command[extension]
	local run_cmd = bufcfg.run_command[extension]
	
	if not compile_cmd and not run_cmd then
		utils.notify("No compile/run command configured for ." .. extension .. " files", "ERROR")
		return
	end
	
	-- Start stress testing in a new window
	M.show_stress_ui(main_file, gen_file, brute_file, compile_cmd, run_cmd, basename, extension, dir)
end

---Show stress testing UI
---@param main_file string path to main solution file
---@param gen_file string path to generator file  
---@param brute_file string path to brute force file
---@param compile_cmd table compile command configuration
---@param run_cmd table run command configuration
---@param basename string base filename without extension
---@param extension string file extension
---@param dir string directory path
function M.show_stress_ui(main_file, gen_file, brute_file, compile_cmd, run_cmd, basename, extension, dir)
	-- Create a new split window for stress testing UI
	vim.cmd("botright split")
	vim.cmd("resize 15")
	
	local ui_bufnr = api.nvim_create_buf(false, true)
	api.nvim_win_set_buf(0, ui_bufnr)
	
	-- Set buffer options
	vim.bo[ui_bufnr].buftype = "nofile"
	vim.bo[ui_bufnr].bufhidden = "wipe"
	vim.bo[ui_bufnr].swapfile = false
	api.nvim_buf_set_name(ui_bufnr, "Stress Test Output")
	
	-- Start stress testing
	M.run_stress_test(ui_bufnr, main_file, gen_file, brute_file, compile_cmd, run_cmd, basename, extension, dir)
end

---Execute the stress testing process
---@param ui_bufnr number buffer number for UI output
---@param main_file string path to main solution file
---@param gen_file string path to generator file
---@param brute_file string path to brute force file  
---@param compile_cmd table compile command configuration
---@param run_cmd table run command configuration
---@param basename string base filename without extension
---@param extension string file extension
---@param dir string directory path
function M.run_stress_test(ui_bufnr, main_file, gen_file, brute_file, compile_cmd, run_cmd, basename, extension, dir)
	local function append_output(text)
		vim.schedule(function()
			if api.nvim_buf_is_valid(ui_bufnr) then
				local lines = vim.split(text, "\n", { plain = true })
				api.nvim_buf_set_lines(ui_bufnr, -1, -1, false, lines)
				-- Scroll to bottom
				local win_ids = vim.fn.win_findbuf(ui_bufnr)
				if #win_ids > 0 then
					local line_count = api.nvim_buf_line_count(ui_bufnr)
					api.nvim_win_set_cursor(win_ids[1], {line_count, 0})
				end
			end
		end)
	end
	
	-- Function to update only the last line (for real-time rendering)
	local function update_last_line(text)
		if api.nvim_buf_is_valid(ui_bufnr) then
			local line_count = api.nvim_buf_line_count(ui_bufnr)
			if line_count > 0 then
				-- Replace the last line with new content
				api.nvim_buf_set_lines(ui_bufnr, line_count - 1, line_count, false, {text})
			else
				-- If buffer is empty, add the line
				api.nvim_buf_set_lines(ui_bufnr, 0, 0, false, {text})
			end
			-- Keep cursor at the bottom and force immediate redraw
			local win_ids = vim.fn.win_findbuf(ui_bufnr)
			if #win_ids > 0 then
				local new_line_count = api.nvim_buf_line_count(ui_bufnr)
				api.nvim_win_set_cursor(win_ids[1], {new_line_count, 0})
			end
			-- Force immediate screen update
			vim.cmd('redraw!')
		end
	end
	
	append_output("🚀 Starting Stress Test...")
	append_output("📁 Directory: " .. dir)
	append_output("📝 Main: " .. basename .. "." .. extension)
	append_output("🎲 Generator: " .. basename .. "_gen." .. extension)
	append_output("🐌 Brute: " .. basename .. "_brute." .. extension)
	append_output("")
	
	-- Debug: show configuration
	append_output("🔍 Debug info:")
	append_output("  Extension: " .. extension)
	append_output("  Compile command: " .. (compile_cmd and vim.inspect(compile_cmd) or "nil"))
	append_output("  Run command: " .. (run_cmd and vim.inspect(run_cmd) or "nil"))
	append_output("")
	
	-- Compilation step
	append_output("🔨 Compiling files...")
	
	local function substitute_modifiers(cmd_table, file_path, file_base, file_ext)
		local result = { exec = cmd_table.exec, args = {} }
		if cmd_table.args then
			for _, arg in ipairs(cmd_table.args) do
				local new_arg = arg
				new_arg = string.gsub(new_arg, "%$%(FNAME%)", vim.fn.fnamemodify(file_path, ":t"))
				new_arg = string.gsub(new_arg, "%$%(FNOEXT%)", file_base)
				new_arg = string.gsub(new_arg, "%$%(FEXT%)", file_ext)
				new_arg = string.gsub(new_arg, "%$%(FABSPATH%)", file_path)
				new_arg = string.gsub(new_arg, "%$%(ABSDIR%)", vim.fn.fnamemodify(file_path, ":p:h"))
				table.insert(result.args, new_arg)
			end
		end
		return result
	end
	
	-- Compile all three files if needed
	local compile_success = true
	if compile_cmd then
		local files_to_compile = {
			{main_file, basename},
			{gen_file, basename .. "_gen"},
			{brute_file, basename .. "_brute"}
		}
		
		for _, file_info in ipairs(files_to_compile) do
			local file_path, file_base = file_info[1], file_info[2]
			local cmd = substitute_modifiers(compile_cmd, file_path, file_base, extension)
			
			append_output("  Compiling " .. vim.fn.fnamemodify(file_path, ":t") .. "...")
			
			-- Build command with proper escaping
			local cmd_parts = {}
			if cmd.exec and cmd.exec ~= "" then
				table.insert(cmd_parts, cmd.exec)
				if cmd.args then
					for _, arg in ipairs(cmd.args) do
						table.insert(cmd_parts, vim.fn.shellescape(arg))
					end
				end
			else
				append_output("❌ No compile command configured")
				compile_success = false
				break
			end
			
			local full_cmd = "cd " .. vim.fn.shellescape(dir) .. " && " .. table.concat(cmd_parts, " ")
			
			-- Debug: show the actual command being executed
			append_output("    Command: " .. full_cmd)
			
			local compile_result = vim.fn.system(full_cmd)
			if vim.v.shell_error ~= 0 then
				append_output("❌ Compilation failed for " .. vim.fn.fnamemodify(file_path, ":t"))
				append_output("Exit code: " .. vim.v.shell_error)
				append_output("Output: " .. compile_result)
				compile_success = false
				break
			else
				append_output("    ✅ Success")
			end
		end
	else
		append_output("⚠️  No compilation needed (interpreted language or no compile command configured)")
	end
	
	if not compile_success then
		append_output("💥 Stress test aborted due to compilation errors")
		return
	end
	
	append_output("✅ All files compiled successfully")
	append_output("")
	
	-- Start stress testing loop
	append_output("🎯 Starting stress test loop...")
	append_output("Press Ctrl+C to stop")
	append_output("")
	append_output("⏳ Preparing to run tests...")  -- This line will be updated in real-time
	
	local test_count = 0
	local max_tests = 1000  -- Maximum number of tests
	local running = true    -- Control flag for stopping
	
	-- Pre-compile command strings for better performance
	local gen_executable = "./" .. vim.fn.shellescape(basename .. "_gen")
	local main_executable = "./" .. vim.fn.shellescape(basename)
	local brute_executable = "./" .. vim.fn.shellescape(basename .. "_brute")
	local cd_cmd = "cd " .. vim.fn.shellescape(dir) .. " && "
	
	-- Recursive function for immediate execution of each test
	local function run_single_test()
		if not running or not api.nvim_buf_is_valid(ui_bufnr) then
			return
		end
		
		test_count = test_count + 1
		if test_count > max_tests then
			append_output("⏹️  Reached maximum test limit (" .. max_tests .. ")")
			running = false
			return
		end
		
		-- Real-time update: show current test progress (overwrites previous line)
		update_last_line(string.format("🎯 Running test #%d...", test_count))
		
		-- Force immediate UI update
		vim.cmd('redraw!')
		
		-- Generate test data
		local input_data = vim.fn.system(cd_cmd .. gen_executable)
		if vim.v.shell_error ~= 0 then
			append_output("❌ Generator failed at test " .. test_count)
			append_output("Command: " .. gen_executable)
			append_output("Exit code: " .. vim.v.shell_error)
			append_output("Output: " .. (input_data or "none"))
			running = false
			return
		end
		
		-- Check if generator produced any output
		if not input_data or input_data:match("^%s*$") then
			append_output("❌ Generator produced no output at test " .. test_count)
			append_output("Command: " .. gen_executable)
			running = false
			return
		end
		
		-- Run main solution
		local main_output = vim.fn.system(cd_cmd .. "echo " .. vim.fn.shellescape(input_data) .. " | " .. main_executable)
		if vim.v.shell_error ~= 0 then
			append_output("❌ Main solution failed at test " .. test_count)
			append_output("Input: " .. input_data:gsub("\n", " "))
			running = false
			return
		end
		
		-- Run brute force solution
		local brute_output = vim.fn.system(cd_cmd .. "echo " .. vim.fn.shellescape(input_data) .. " | " .. brute_executable)
		if vim.v.shell_error ~= 0 then
			append_output("❌ Brute force solution failed at test " .. test_count)
			append_output("Input: " .. input_data:gsub("\n", " "))
			running = false
			return
		end
		
		-- Compare outputs
		local main_clean = main_output:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
		local brute_clean = brute_output:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
		
		if main_clean == brute_clean then
			-- Test passed - update the current line with pass status
			update_last_line(string.format("✅ Test #%d passed (ongoing...)", test_count))
			
			-- Schedule next test immediately using vim.schedule for event loop processing
			vim.schedule(function()
				vim.defer_fn(run_single_test, 0)  -- Immediate execution but allows UI refresh
			end)
		else
			-- Test failed - found difference!
			append_output("💥 DIFFERENCE FOUND at test " .. test_count .. "!")
			append_output("")
			append_output("📥 Input:")
			append_output(input_data)
			append_output("📤 Main output:")
			append_output(main_output)
			append_output("📤 Brute output:")
			append_output(brute_output)
			append_output("")
			append_output("🔍 Check your main solution for bugs!")
			
			running = false
			return
		end
	end
	
	-- Start the first test with a small delay to ensure UI is ready
	vim.defer_fn(run_single_test, 100)  -- 100ms initial delay
	
	-- Add keymap to stop stress testing
	api.nvim_buf_set_keymap(ui_bufnr, 'n', '<C-c>', '', {
		noremap = true,
		silent = true,
		callback = function()
			running = false
			append_output("")
			append_output("⏹️  Stress test stopped by user")
			append_output("✅ Completed " .. test_count .. " tests")
		end
	})
	
	api.nvim_buf_set_keymap(ui_bufnr, 'n', 'q', '', {
		noremap = true,
		silent = true,
		callback = function()
			running = false
			vim.cmd("q")
		end
	})
end

return M

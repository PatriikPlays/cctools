-- Copyright (c) 2024 Patriik
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


-- FIXME: repoPath download downloads incorrectly, dont care enough to fix it

local function printf(...)
    print(string.format(...))
end

local function errorf(...)
    error(string.format(...))
end

local function fetchDirectoryContents(owner, repo, path, branch)
  local url = string.format("https://api.github.com/repos/%s/%s/contents/%s?ref=%s", owner, repo, path or "", branch)
  local response, errCode, err = http.get(url)

  if response then
    local contents = textutils.unserializeJSON(response.readAll())
    if contents and type(contents) == "table" then
      return contents
    end
  end

  local msg
  if err then
    local str = err.readAll()
    print(str)
    local parsed = textutils.unserializeJSON(str)
    if parsed then
        msg = parsed.message
    end
  end

  errorf("Failed to get conntents of dir %s: %s; %s", path, tostring(errCode), msg or "unknown")
end

local function downloadFile(url, path)
  if fs.exists(path) then
    error("Path " .. path .. " already exists, refusing to overwrite.")
  end

  local response, errCode, err = http.get(url)
  if response then
    local content = response.readAll()
    local file = fs.open(path, "w")
    file.write(content)
    file.close()
    return true
  else
    local msg
    if err then
        local str = err.readAll()
        print(str)
        local parsed = textutils.unserializeJSON(str)
        if parsed then
            msg = parsed.message
        end
    end

    errorf("Failed to download file at %s: %s; %s", url, errCode, msg or unknown)
  end
end

local function indexRepo(owner, repo, repoPath, branch, files, dirs)
    printf("Indexing %s", repoPath)
    files = files or {}
    dirs = dirs or {}

    local contents = fetchDirectoryContents(owner, repo, repoPath, branch)
    for _, item in pairs(contents) do
        if item.type == "file" then
            print("Found file " .. item.path)
            files[item.path] = item.download_url
        elseif item.type == "dir" then
            print("Found dir " .. item.path)
            dirs[#dirs+1] = item.path
            indexRepo(owner, repo, item.path, branch, files, dirs)
        end
    end

    return files,dirs
end

--[[
local function downloadRepoContents(owner, repo, repoPath, localPath, branch)
  local contents = fetchDirectoryContents(owner, repo, repoPath, branch)
  for _, item in pairs(contents) do
    if item.type == "file" then
      print("Downloading " .. item.path)
      downloadFile(item.download_url, fs.combine(localPath, item.path))
    elseif item.type == "dir" then
      local newLocalPath = fs.combine(localPath, item.path)
      if not fs.exists(newLocalPath) then
        fs.makeDir(newLocalPath)
      end

      downloadRepoContents(owner, repo, item.path, newLocalPath, branch)
    end
  end
end
--]]

local function downloadRepoContents(owner, repo, repoPath, localPath, branch, maxParallel)
    -- repoPath partially broken!!
    fs.makeDir(localPath)

    local files, dirs = indexRepo(owner, repo, repoPath, branch)

    for _,v in ipairs(dirs) do
        fs.makeDir(fs.combine(localPath, v))
    end

    local index = {}

    for k,_ in pairs(files) do
        index[#index+1] = k
    end

    local workers = {}
    for i=1,maxParallel do
        workers[i] = function()
            while true do
                local file = index[1]
                if not file then
                    return
                end
                table.remove(index, 1)

                printf("Downloading %s", file)
                downloadFile(files[file], fs.combine(localPath, file))
            end
        end
    end

    parallel.waitForAll(table.unpack(workers))
end

local function clone(owner, repo, repoPath, localPath, branch, maxParallel)
    if fs.exists(localPath) then
        error("Local path already exists")
    end

    local s,e = pcall(downloadRepoContents, owner, repo, repoPath, localPath, branch, maxParallel)
    if not s then
        fs.delete(localPath)
        printError(e)
    end
end

local owner, repo, localPath, branch, maxParallel = ...

maxParallel = tonumber(maxParallel or 4) or 4
branch = branch or "main"

if not (owner and repo and localPath) then
    printError("Usage: ghclone.lua <owner> <repo> <localPath> <branch> <maxParallel>")
    return
end

clone(owner, repo, "/", localPath, branch, maxParallel)

local M = {}




local api = require("crates.api")
local Version = api.Version
local async = require("crates.async")
local core = require("crates.core")
local diagnostic = require("crates.diagnostic")
local toml = require("crates.toml")
local ui = require("crates.ui")
local util = require("crates.util")

M.reload_deps = async.wrap(function(crate_name, versions, version)
   local deps, cancelled = api.fetch_deps(crate_name, version.num)
   if cancelled then return end

   if deps then
      version.deps = deps
      for _, d in ipairs(deps) do

         if d.opt and not version.features:get_feat(d.name) then
            table.insert(version.features, {
               name = d.name,
               members = {},
            })
         end
      end
      version.features:sort()

      for b, crates in pairs(core.crate_cache) do

         for _, c in pairs(crates) do
            if c.name == crate_name then
               local avoid_pre = core.cfg.avoid_prerelease and not c:vers_is_pre()
               local m, p, y = util.get_newest(versions, avoid_pre, c:vers_reqs())
               local match = m or p or y

               if c.vers and match == version and vim.api.nvim_buf_is_loaded(b) then
                  local diagnostics = diagnostic.process_crate_deps(c, version, deps)
                  ui.display_diagnostics(b, diagnostics)
               end
            end
         end
      end
   end
end)

M.reload_crate = async.wrap(function(crate_name)
   local versions, cancelled = api.fetch_vers(crate_name)
   if cancelled then return end

   if versions and versions[1] then
      core.vers_cache[crate_name] = versions
   end

   for b, crates in pairs(core.crate_cache) do

      for _, c in pairs(crates) do
         if c.name == crate_name and vim.api.nvim_buf_is_loaded(b) then
            local info = diagnostic.process_crate_versions(c, versions)
            ui.display_crate_info(b, info)

            if versions and versions[1] then
               M.reload_deps(c.name, versions, info.version or versions[1])
            end
         end
      end
   end
end)

function M.update(buf, reload)
   if reload then
      core.vers_cache = {}
      api.cancel_jobs()
   end

   buf = buf or util.current_buf()
   local sections, crates = toml.parse_crates(buf)
   local cache, diagnostics = diagnostic.process_crates(sections, crates)

   ui.clear(buf)
   ui.display_diagnostics(buf, diagnostics)
   for _, c in pairs(cache) do
      local versions = core.vers_cache[c.name]

      if not reload and versions then
         local info = diagnostic.process_crate_versions(c, versions)
         ui.display_crate_info(buf, info)

         local version = info.version or versions[1]
         if version.deps then
            diagnostics = diagnostic.process_crate_deps(c, version, version.deps)
            ui.display_diagnostics(buf, diagnostics)
         else
            M.reload_deps(c.name, versions, version)
         end
      else
         if core.cfg.loading_indicator then
            ui.display_loading(buf, c)
         end

         M.reload_crate(c.name)
      end
   end

   core.crate_cache[buf] = cache
end

return M

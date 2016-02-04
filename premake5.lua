
-- Option to allow copying the DLL file to a custom folder after build
newoption {
	trigger = "copy-to",
	description = "Optional, copy the DLL to a custom folder after build, define the path here if wanted.",
	value = "PATH"
}

newoption {
	trigger = "no-new-structure",
	description = "Do not use new virtual path structure (separating headers and source files)."
}

newaction {
	trigger = "version",
	description = "Returns the version string for the current commit of the source code.",
	onWorkspace = function(wks)
		-- get revision number via git
		local proc = assert(io.popen("git rev-list --count HEAD", "r"))
		local revNumber = assert(proc:read('*a')):gsub("%s+", "")
		proc:close()

		print(revNumber)
		os.exit(0)
	end
}

newaction {
	trigger = "generate-buildinfo",
	description = "Sets up build information file like version.h.",
	onWorkspace = function(wks)
		-- get revision number via git
		local proc = assert(io.popen("git rev-list --count HEAD", "r"))
		local revNumber = assert(proc:read('*a')):gsub("%s+", "")
		proc:close()

		-- get old version number from version.hpp if any
		local oldRevNumber = "(none)"
		local oldVersionHeader = io.open(wks.location .. "/version.hpp", "r")
		if oldVersionHeader ~=nil then
			local oldVersionHeaderContent = assert(oldVersionHeader:read('*a'))
			oldRevNumber = string.match(oldVersionHeaderContent, "#define REVISION (%d+)")
			if oldRevNumber == nil then
				-- old version.hpp format?
				oldRevNumber = "(none)"
			end
		end

		-- generate version.hpp with a revision number if not equal
		if oldRevNumber ~= revNumber then
			print ("Update " .. oldRevNumber .. " -> " .. revNumber)
			local versionHeader = assert(io.open(wks.location .. "/version.hpp", "w"))
			versionHeader:write("/*\n")
			versionHeader:write(" * Automatically generated by premake5.\n")
			versionHeader:write(" * Do not touch, you fucking moron!\n")
			versionHeader:write(" */\n")
			versionHeader:write("\n")
			versionHeader:write("#define REVISION " .. revNumber .. "\n")
			versionHeader:close()
		end
	end
}

workspace "iw4x"
	location "./build"
	objdir "%{wks.location}/obj"
	targetdir "%{wks.location}/bin/%{cfg.buildcfg}"
	configurations { "Debug", "DebugStatic", "Release", "ReleaseStatic" }
	architecture "x32"
	platforms "x86"

	-- VS 2015 toolset only
	toolset "msc-140"

	configuration "windows"
		defines { "_WINDOWS" }

	configuration "Release*"
		defines { "NDEBUG" }
		flags { "MultiProcessorCompile", "Symbols", "LinkTimeOptimization", "No64BitChecks" }
		optimize "Full"

	configuration "Debug*"
		defines { "DEBUG", "_DEBUG" }
		flags { "MultiProcessorCompile", "Symbols", "No64BitChecks" }
		optimize "Debug"

	configuration "*Static"
		flags { "StaticRuntime" }

	project "iw4x"
		kind "SharedLib"
		language "C++"
		files { "./src/**.hpp", "./src/**.cpp" }
		includedirs { "%{prj.location}", "./src" }

		-- Pre-compiled header
		pchheader "STDInclude.hpp" -- must be exactly same as used in #include directives
		pchsource "src/STDInclude.cpp" -- real path
		buildoptions { "-Zm200" } -- allocate ~150mb memory for the precompiled header. This should be enough, increase if necessary

		-- Dependency on zlib, json11 and asio
		links { "zlib", "json11", "pdcurses", "libtomcrypt", "libtommath" }
		includedirs 
		{ 
			"./deps/zlib",
			"./deps/json11", 
			"./deps/pdcurses", 
			"./deps/asio/asio/include",
			"./deps/libtomcrypt/src/headers",
			"./deps/libtommath",
		}

		-- Virtual paths
		if not _OPTIONS["no-new-structure"] then
			vpaths {
				["Headers/*"] = "./src/**.hpp",
				["Sources/*"] = {"./src/**.cpp"}
			}
		end

		vpaths {
			["Docs/*"] = {"**.txt","**.md"}
		}

		-- Pre-build
		prebuildcommands {
			"cd %{_MAIN_SCRIPT_DIR}",
			"premake5 generate-buildinfo"
		}

		-- Post-build
		if _OPTIONS["copy-to"] then
			saneCopyToPath = string.gsub(_OPTIONS["copy-to"] .. "\\", "\\\\", "\\")
			postbuildcommands {
				"copy /y \"$(TargetDir)*.dll\" \"" .. saneCopyToPath .. "\""
			}
		end

		-- Specific configurations
		flags { "UndefinedIdentifiers", "ExtraWarnings" }

		configuration "Release*"
			flags { "FatalCompileWarnings" }

	group "External dependencies"

		-- zlib
		project "zlib"
			language "C"
			defines { "ZLIB_DLL", "_CRT_SECURE_NO_DEPRECATE" }

			files
			{
				"./deps/zlib/*.h",
				"./deps/zlib/*.c"
			}

			-- not our code, ignore POSIX usage warnings for now
			warnings "Off"

			kind "SharedLib"
			configuration "*Static"
				kind "StaticLib"
				removedefines { "ZLIB_DLL" }
				
				
		-- json11
		project "json11"
			language "C++"

			files
			{
				"./deps/json11/*.cpp",
				"./deps/json11/*.hpp"
			}
			
			-- remove dropbox's testing code
			removefiles { "./deps/json11/test.cpp" }

			-- not our code, ignore POSIX usage warnings for now
			warnings "Off"

			-- always build as static lib, as json11 doesn't export anything
			kind "StaticLib"
			
			
		-- pdcurses
		project "pdcurses"
			language "C"
			includedirs { "./deps/pdcurses/"  }

			files
			{
				"./deps/pdcurses/pdcurses/*.c",
				"./deps/pdcurses/win32/*.c"
			}

			-- not our code, ignore POSIX usage warnings for now
			warnings "Off"

			-- always build as static lib, as pdcurses doesn't export anything
			kind "StaticLib"

		-- libtomcrypt
		project "libtomcrypt"
			language "C"
			defines { "_LIB", "LTC_SOURCE", "LTC_NO_RSA_BLINDING", "LTM_DESC", "USE_LTM" }
			
			links { "libtommath" }
			includedirs { "./deps/libtomcrypt/src/headers"  }
			includedirs { "./deps/libtommath"  }

			files { "./deps/libtomcrypt/src/**.c" }
			
			-- seems like tab stuff can be omitted
			removefiles { "./deps/libtomcrypt/src/**/*tab.c" }
			
			-- remove incorrect files
			-- for some reason, they lack the necessary header files
			-- i might have to open a pull request which includes them
			removefiles 
			{ 
				"./deps/libtomcrypt/src/pk/dh/dh_sys.c",
				"./deps/libtomcrypt/src/hashes/sha2/sha224.c",
				"./deps/libtomcrypt/src/hashes/sha2/sha384.c",
				"./deps/libtomcrypt/src/encauth/ocb3/**.c",
			}

			-- not our code, ignore POSIX usage warnings for now
			warnings "Off"

			-- always build as static lib, as pdcurses doesn't export anything
			kind "StaticLib"
			
		-- libtommath
		project "libtommath"
			language "C"
			defines { "_LIB" }
			includedirs { "./deps/libtommath"  }

			files { "./deps/libtommath/*.c" }

			-- not our code, ignore POSIX usage warnings for now
			warnings "Off"

			-- always build as static lib, as pdcurses doesn't export anything
			kind "StaticLib"

--[[

This file implements the instruction engine portion of LNVL.  Please
see the document

    docs/Instructions.md

for details about this system and its design.

--]]

-- Create our Instruction class.
local Instruction = {}
Instruction.__index = Instruction

-- This is a list of all the valid instructions.
Instruction.ValidInstructions = {
    ["say"] = true,
    ["set-image"] = true,
    ["draw-image"] = true,
    ["set-scene"] = true,
    ["no-op"] = true,
    ["show-menu"] = true,
    ["set-position"] = true,
    ["set-name"] = true,
    ["set-color"] = true,
    ["set-font"] = true,
    ["set-data"] = true,
    ["get-data"] = true,
}

-- Our constructor.  It requires a table with two properties, named
-- and defined in comments within the constructor.
function Instruction:new(properties)
    local instruction = {}
    setmetatable(instruction, Instruction)
    LNVL.Debug.Log.check(Instruction.ValidInstructions[properties.name] ~= nil,
                         string.format("Unknown instruction %s", properties.name),
                         "fatal")

    -- name: The name of the instruction as a string.
    instruction.name = properties.name

    -- action: A function representing the logic for the instruction.
    instruction.action = properties.action

    return instruction
end

-- A simple tostring() method for debugging purposes, which does
-- nothing but returns the name of the instruction.
Instruction.__tostring = function (instruction)
    return string.format("<Instruction %s>", instruction.name)
end

-- We define a __call() metatable method as a shortcut for executing
-- the 'action' function of an instruction.
Instruction.__call = function (f, ...)
    if type(f) == "function" then
        return f(...)
    else
        return f.action(...)
    end
end

-- This table contains all of the instructions in the LNVL engine.
-- The keys for the table are strings, the names of the instructions.
-- The values are the Instruction objects themselves.
--
-- All of the individual instructions defined below are described in
-- detail by the document referenced at the top of this file.  None of
-- the instruction action functions return values.
local Implementations = {}

Implementations["say"] = Instruction:new {
    name = "say",
    action = function (arguments)
        local font = arguments.scene.font
        local textColor = arguments.scene.textColor or LNVL.Settings.Characters.TextColor

        -- Interpolate any variables that may be in the content.
        local content = string.gsub(arguments.content, "<<(%w+)>>", LNVL.ScriptEnvironment)

        if arguments["character"] ~= nil then
			local displaySpeed = arguments.scene.speedTable[arguments.character.dialogName] or 
			arguments.character.dialogSpeed
            -- If the text is spoken by a character then we can add
            -- additional formatting to the output, such as the
            -- character's name and font if present.
            LNVL.Graphics.DrawText {
                font,
                arguments.character.textColor,
   				displaySpeed,
                string.format("%s: %s",
                              arguments.character.dialogName,
                              content) }
        else
            LNVL.Graphics.DrawText{font, textColor, content}
        end
    end }

Implementations["set-name"] = Instruction:new {
    name = "set-name",
    action = function (arguments)
        local character, name = arguments.target, arguments.name
        LNVL.Debug.Log.check(getmetatable(character) == LNVL.Character,
                             "set-name instruction must receive a Character.",
                             "error")
        
        if name == "default" then
            character.dialogName = character.firstName
        elseif name == "fullName" then
            character.dialogName = ("%s %s"):format(character.firstName, character.lastName)
        else
            character.dialogName = character[name]
        end
    end
}

Implementations["set-data"] = Instruction:new {
    name = "set-data",
    action = function (arguments)
        rawset(LNVL.ScriptEnvironment, arguments.name, arguments.value)
    end
}

Implementations["get-data"] = Instruction:new {
    name = "get-data",
    action = function (arguments)
        local content = rawget(LNVL.ScriptEnvironment, arguments.name)
        local font = arguments.scene.font
        local textColor = arguments.scene.textColor or LNVL.Settings.Characters.TextColor
        LNVL.Graphics.DrawText{font, textColor, content}
    end
}

Implementations["set-color"] = Instruction:new {
    name = "set-color",
    action = function (arguments)
        LNVL.Debug.Log.check(getmetatable(arguments.target) == LNVL.Character,
                             "set-color instruction must receive a Character.",
                             "error")
        arguments.target.textColor = arguments.color
    end
}

Implementations["set-font"] = Instruction:new {
    name = "set-font",
    action = function (arguments)
        LNVL.Debug.Log.check(getmetatable(arguments.target) == LNVL.Character,
                             "set-font instruction must receive a Character.",
                             "error")
        arguments.target.font =
            love.graphics.newFont(arguments.font .. ".ttf", arguments.size)
    end
}

Implementations["set-image"] = Instruction:new {
    name = "set-image",
    action = function (arguments)
        local targetType = getmetatable(arguments.target)

        if targetType == LNVL.Character then
            -- If the target is a Character then we change their
            -- 'currentImage' to the new one in the instruction.
            arguments.target.currentImage = arguments.image
        elseif targetType == LNVL.Scene then
            -- If the target is a Scene we change its background
            -- image.  However, first we need to assign the 'scene'
            -- parameter of the argument to the 'target'.  The
            -- commentary for LNVL.Opcode.Processor["set-scene-image"]
            -- explains why we must do this here.
            arguments.target = arguments.scene
            arguments.target.backgroundImage = arguments.image
        else
            -- If we reach this point then it is an error.
            LNVL.Debug.Log.error(string.format("Cannot set-image for %s", targetType))
        end
    end }

Implementations["draw-image"] = Instruction:new {
    name = "draw-image",
    action = function (arguments)
        love.graphics.setColor(LNVL.Color.White)

        -- If we have arguments for a border then we assign those to
        -- the relevant properties of the image, assuming it is a
        -- Drawable object.  That way the call to image:draw() will
        -- include the border.
        if arguments["border"] ~= nil then
            if getmetatable(arguments.image) == LNVL.Drawable then
                arguments.image.borderColor = arguments.border[1]
                arguments.image.borderSize = arguments.border[2]
            end
        end

        if getmetatable(arguments.image) == LNVL.Drawable then
            if arguments["position"] ~= nil then
                arguments.image:setPosition(arguments.position)
            end

            arguments.image:draw()
        else
            love.graphics.draw(arguments.image,
                               arguments.location[1],
                               arguments.location[2])
        end
end }

Implementations["set-scene"] = Instruction:new {
    name = "set-scene",
    action = function (arguments)
       local target = arguments.target
       local name

       -- The target must be either a string or a function.  For
       -- details on why see the implementation of 'ChangeToScene' in
       -- the src/scene.lua file.
       if type(target) == "string" then
	  name = target
       elseif type(target) == "function" then
	  name = target(arguments.scene)
	  LNVL.Debug.Log.check(type(name) == "string",
                               "set-scene instruction must receive a string.",
                               "error")
       else
	  LNVL.Debug.Log.error("Invalid target for set-scene: " .. target)
       end

       LNVL.ChangeToScene(name)
    end
}

Implementations["no-op"] = Instruction:new {
    name = "no-op",
    action = function (arguments)
        LNVL.Debug.Log.error("The engine must never generate a no-op instruction.")
    end
}

Implementations["show-menu"] = Instruction:new {
		name = "show-menu",
		action = function (arguments)
		if LNVL.Settings.Handlers.Menu == nil or
		coroutine.status(LNVL.Settings.Handlers.Menu) == "dead" then
			LNVL.Settings.Handlers.Menu = coroutine.create(
				function (menu)
					return next(menu)
				end
			)
		end
		local executed, choice = coroutine.resume(
			LNVL.Settings.Handlers.Menu,
			arguments.menu
		)
        if executed == true then
            arguments.menu.currentChoiceIndex = choice
        end
    end
}

Implementations["set-position"] = Instruction:new {
    name = "set-position",
    action = function (arguments)
        arguments.target.position = arguments.position
    end
}

-- This table has the names of opcodes for strings and maps them to
-- the names of the instructions we execute for each opcode.  Note
-- that there is not a one-to-one mapping between opcodes and
-- instructions; different opcodes may become the same instruction.
Instruction.ForOpcode = {
    ["say"] = Implementations["say"],
    ["think"] = Implementations["say"],
    ["set-character-image"] = Implementations["set-image"],
    ["set-character-name"] = Implementations["set-name"],
    ["set-character-text-color"] = Implementations["set-color"],
    ["set-character-text-font"] = Implementations["set-font"],
    ["change-scene"] = Implementations["set-scene"],
    ["set-scene-image"] = Implementations["set-image"],
    ["no-op"] = Implementations["no-op"],
    ["deactivate-character"] = Implementations["no-op"],
    ["move-character"] = Implementations["set-position"],
    ["add-menu"] = Implementations["show-menu"],
    ["export-variable"] = Implementations["set-data"],
    ["import-variable"] = Implementations["get-data"],
}

-- If LNVL is running in debugging mode then make sure that every
-- instruction we list as valid has a match Instruction object
-- that implements it.
--
-- We also make sure that every opcode has a matching instruction.
if LNVL.Settings.DebugModeEnabled == true then
    for name,_ in pairs(Instruction.ValidInstructions) do
        if Implementations[name] == nil then
            LNVL.Debug.Log.fatal("No implementation for the instruction " .. name)
        end
    end

    for name,_ in pairs(LNVL.Opcode.ValidOpcodes) do
        if Instruction.ForOpcode[name] == nil
            or getmetatable(Instruction.ForOpcode[name]) ~= Instruction
        then
            LNVL.Debug.Log.fatal("No instruction implementation for the opcode " .. name)
        end
    end
end

-- Return our class as a module.
return Instruction

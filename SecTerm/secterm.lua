--- Variables ---
-- Libs
local term = require("term")
local computer = require("computer")
local component = require("component")
local text = require("text")
local serialization = require("serialization")
local sides = require("sides")
local colors = require("colors")
local event = require("event")
local fs = require("filesystem")
local rc = require("rc")
-- Shortened
local gpu = component.gpu
local data = component.isAvailable("data") and component.data or nil
local redstone = component.isAvailable("redstone") and component.redstone or nil
local color = gpu.setForeground
local getResolution = gpu.getResolution
local setResolution = gpu.setResolution
local maxResolution = gpu.maxResolution
local getDepth = gpu.getDepth
local sleep = os.sleep
local write = io.write
local open = io.open
local pack = table.pack
local unpack = table.unpack
local insert = table.insert
local remove = table.remove
local match = string.match
local gmatch = string.gmatch
local find = string.find
local gsub = string.gsub
local fmod = math.fmod
local floor = math.floor
local log = math.log
local exec = os.execute
local date = os.date
local exit = os.exit
local traceback = debug.traceback
local serialize = serialization.serialize
local unserialize = serialization.unserialize
local read = term.read
local clear = term.clear
local clearln = term.clearLine
-- Global
local terminateFlag = false  -- True = terminate execution of main program
local restartFlag = false    -- True = restart after termination
local errLog                 -- File
local settings               -- [entry][controlled components][1 for channel (is 1-16 or false), 2 for side (is 0-5 or false), 3 for strength when on (is 1-15 or false)]
local redState               -- [side (0-5)][channel (1-16) or -1 for normal redstone (is )]
local resolution             -- [1 for width, 2 for height]
local side                   -- INT 0 - 5
local dobeep                 -- True = activate beeper
local passwd                 -- SHA256 hash
local firstRun               -- True = first time running the program properly
-- Const
local settingsFile = "/etc/secterm.conf"
local rcFile = "/etc/rc.d/secterm.lua"
local logDir = "/var/log"
local logFile = logDir .. "/secterm.log"
local minRes = {80,25}
local colorHex = {0xFFFFFF, 0xFFA500, 0xFF00FF, 0xADD8E6, 0xFFFF00, 0x00FF00, 0xFFC0CB, 0x808080, 0xC0C0C0, 0x00FFFF, 0x800080, 0x0000FF, 0x8B4513, 0x008000, 0xFF0000, 0xA9A9A9}
local nativeRes = pack(getResolution())
local helpPage = [[
        --- About SecTerm ---

This program was initially developed by Alex811.
The files used by this program are licenced under the MIT license (Expat).
You may use, distribute, modify, etc. this program as you see fit,
but I would appreciate it if you gave me appropriate credit.

Please keep in mind the following:
  This program is designed to run on OpenComputers with:
    a tier 2 or higher GPU (tier 3 recommended),
    a tier 2 or higher screen (a big one for the best experience ^-^),
    a tier 2 redstone card (bundled cables won't work with tier 1),
    a tier 1 or higher data card,
    enough memory.
  This program is designed to be used with ProjectRed Bundled Cables.
  It might work fine with RedPower2 or even EnderIO Redstone Conduits
  in some versions.
  The default side used to control redstone is the back.
  The default password is empty.
  The only way to exit the program is through the settings menu.
]]
local redInfoPage = [[
This program is designed to be used with ProjectRed Bundled Cables.
When you create a menu item, you choose which channel it will control
using numbers (1-16). Each number matches a channel color.
Here are the channel colors, their numbers and their current state:
]]
local itemInfoPage = [[
Each item controls one or more ProjectRed Bundled Cable channel (color).
If no channel is specified, the side will be controlled with normal redstone.
To not use the default side for a channel, you can specify a side override.
You can also specify how strong you want the signal to be for each one.
You specify everything with a number prepended by a letter, c for channel,
s for side override, p for power (redstone strength, when on, 15 by default).
You can find the channel numbers under "Redstone/channel info" and the
side numbers under "Side info"!
You can specify multiple channels to be controlled, separated by commas.
Example: c2, c4 s2 p10
This will control channel 2 of the default side with a strength of 15
and channel 4 of the 2nd side with a strength of 10.
To abort, leave the title blank!
]]
local rcScript = [[
function start()
    os.execute("secterm service")
end
]]

--- Functions ---
function about()
    clear()
    print(helpPage)
    sleep(.5)
    waitEnter()
end

function beep(...)
    if dobeep then
        computer.beep(...)
    end
end

function redMap(n)  -- Map enderIO color sequence to color API numbers (the tool just uses that sequence since an older version that was made specifically for EnderIO conduits and I thought I'd keep it)
    if n then
        return fmod((31 - n),16)
    else
        return false
    end
end

function colorState(b, --[[optional]]noNL)  -- Print a green "ON" or a red "OFF" according to the argument
    if b then
        prtGood("ON", noNL)
    else
        prtBad("OFF", noNL)
    end
end

function terminate(--[[optional]]restart)  -- Terminate execution
    terminateFlag = true
    restartFlag = restart or false
    prtWarn("Terminating execution" .. (restart and "(restarting)" or "") .. "...")
    beep(500)
    beep(120, .3)
end

function loadSettings()  -- Load settings file into memory
    local file = open(settingsFile, "r")
    passwd = data.decode64(file:read("*l"))
    firstRun = unserialize(file:read("*l"))
    dobeep = unserialize(file:read("*l"))
    side = tonumber(unserialize(file:read("*l")))
    resolution = unserialize(file:read("*l"))
    redState = unserialize(file:read("*l"))
    settings = unserialize(file:read("*l"))
    file:close()
    prtWarn("Settings loaded!")
end

function saveSettings()  -- Save settings file from memory
    local file = open(settingsFile, "w")
    file:write(data.encode64(passwd).."\n")
    file:write(serialize(firstRun) .. "\n")
    file:write(serialize(dobeep) .. "\n")
    file:write(serialize(side) .. "\n")
    file:write(serialize(resolution) .. "\n")
    file:write(serialize(redState) .. "\n")
    file:write(serialize(settings) .. "\n")
    file:close()
    prtWarn("Settings saved!")
end

function prtHR()
    local hr = ""
    for i = 1, pack(getResolution())[1], 1 do
        hr = hr .. "-"
    end
    print(hr)
end

function prtColoredMsg(msg, msgColor, --[[optional]]noNL)
    color(msgColor)
    write(msg .. (noNL and "" or "\n"))
    color(0xFFFFFF)
end

function prtColoredColor(n)
    if n then
        if getDepth() < 8 then
            write(colors[n])
        else
            prtColoredMsg(colors[n], colorHex[n + 1], true)
        end
    else
        write("normal")
    end
end

function prtGood(msg, --[[optional]]noNL)
    prtColoredMsg(msg, 0x00FF00, noNL)
end

function prtWarn(msg, --[[optional]]noNL)
    prtColoredMsg(msg, 0xFFFF00, noNL)
end

function prtBad(msg, --[[optional]]noNL)
    prtColoredMsg(msg, 0xFF0000, noNL)
end

function prtPrompt(msg)
    prtColoredMsg(msg, 0x99B2F2, true)
end

function prtHeader(msg)
    prtColoredMsg(msg, 0x0000FF)
end

function prtOpts(maxNum4Padding)  -- Print available options added by the user
    for i = 1, #settings, 1 do
        sleep(.05)
        print(i .. ". " .. getPadding(i, maxNum4Padding) .. settings[i][1])
    end
end

function coloredRead(...)
    color(0xFFAA00)
    local input = read(...)
    color(0xFFFFFF)
    return input
end

function ask(prompt)
    prtPrompt(prompt .. ": ")
    return coloredRead()
end

function waitEnter(--[[optional]]startWithNL)
    prtPrompt((startWithNL and "\n" or "") .. "Press Enter to continue...")
    read()
end

function sideListStr()  -- returns a string with a list of sides separated by commas
    local s = ""
    for i = 0, 5, 1 do
        s = s .. sides[i] .. (i < 5 and ", " or "")
    end
    return s
end

function digitNum(num)  -- Returns number of digits in num
    return floor(log(num, 10) + 1)
end

function getPadding(num, max)  -- Returns a padding to align numbers, num's the current number, max is the biggest number that will be printed
    local padding = ""
    local r = digitNum(max) - digitNum(num)
    for _ = 1, r, 1 do
        padding = padding .. " "
    end
    return padding
end

function readPW(prompt)  -- Reads password input and returns hash
    prtPrompt(prompt .. ": ")
    local input = coloredRead({}, false, {}, "*")
    clearln()
    return input and data.sha256(text.trim(input)) or false
end

function verifyPW(prompt)  -- Check password
    local input = readPW(prompt)
    color(0xe57fd8)
    for _ = 1, 5, 1 do
        write(".")
        sleep(.05)
    end
    clearln()
    return input == passwd
end

function setPW()  -- Change password
    clear()
    local verifyCurr = verifyPW("Enter current password")
    if verifyCurr then
        local input = readPW("New password")
        if input then
            if input == readPW("Repeat password") then
                passwd = input
                saveSettings()
                prtGood("Password changed successfully.")
            else
                prtBad("Passwords didn't match.")
            end
        end
    else
        prtBad("Wrong password.")
    end
    sleep(1.5)
end

function getRed(channel, ctrlSide)  -- Get digital redstone signal
    return channel and (redstone.getBundledOutput(ctrlSide, channel) > 0) or (redstone.getOutput(ctrlSide) > 0)
end

function setRedState(ctrlSide, channel, power)
    if not redState[ctrlSide] then redState[ctrlSide] = {} end
    redState[ctrlSide][channel] = power
end

function getRedState(ctrlSide, channel)
    return redState[ctrlSide] and redState[ctrlSide][channel] or nil
end

function setRed(channel, ctrlSide, power, --[[optional]]noSave)  -- Set redstone signal
    if not power then return end
    local s = ctrlSide or side
    if getRed(channel, s) ~= (power > 0) then    -- If requested state is different than current
        if channel then
            redstone.setBundledOutput(s, channel, power)    -- Set state
            if not noSave then setRedState(s, channel + 1, power) end   -- Save state to memory
        else
            redstone.setOutput(s, power)    -- Set state
            if not noSave then setRedState(s, -1, power) end    -- Save state to memory
        end
        beep(power > 0 and 520 or 420, .04)
    end
end

function setRedAll(settingsIndex, state)  -- set state of all components of a settings item
    for item = 2, #settings[settingsIndex], 1 do
        local c = settings[settingsIndex][item][1]
        local s = settings[settingsIndex][item][2] or side
        local p = settings[settingsIndex][item][3] or 15
        local mappedC = redMap(c)
        setRed(mappedC, s, state and p or 0)
    end
end

function redResume()  -- Set redstone states from memory
    print("Restoring redstone states...")
    for s = 0, 5, 1 do
        for c = 0, 15, 1 do
            setRed(c, s, getRedState(s, c), true)  -- Restore channels
        end
        setRed(false, s, getRedState(s, -1), true)  -- Restore normal redstone
    end
end

function checkHardware()  -- Test hardware compatibility and display errors (also tries to set the selected resolution)
    local w, h = maxResolution()
    print("Checking hardware...")
    if w >= resolution[1] and h >= resolution[2] then
        local currRes = pack(getResolution())
        if setResolution(unpack(resolution)) or (currRes[1] == resolution[1] and currRes[2] == resolution[2]) then
            if component.isAvailable("redstone") then
                if component.isAvailable("data") then
                    return  -- Everything OK
                else
                    prtWarn("Data component not found.")
                end
            else
                prtWarn("Redstone component not found.")
            end
        else
            prtWarn("Unable to set resolution, too small screen or too weak GPU!")
        end
    else
        prtWarn("Unable to set resolution, too small screen or too weak GPU!")
    end
    prtBad("Fatal error: please upgrade your hardware and try again.\nTerminating...\n")
    color(0xFF00FF)
    for _ = 1, 10, 1 do
        write(".")
        beep(150)
        sleep(.6)
    end
    color(0xFFFFFF)
    clearln()
    terminate()
end

function init(...)  -- Initialize program and terminal
    clear()
    event.shouldInterrupt = function() return false end  -- Disable interrupts
    print("Initializing...")
    sleep(1)
    if not fs.exists(rcFile) then  -- Generate service file
        local file = open(rcFile, "w")
        file:write(rcScript)
        file:close()
    end
    if not fs.exists(logDir) then  -- Generate log dir
        fs.makeDirectory(logDir)
    end
    errLog = open(logFile,"a")  -- Open log file
    if redstone and data then  -- Only load settings file if the hardware is okay
        if not fs.exists(settingsFile) then  -- Generate settings if they don't exist
            setDefaults()
        end
        loadSettings()  -- Load to memory
    else  -- Fallback
        resolution = {80, 25}
        dobeep = true
    end
    if firstRun then  -- If first run, display about page
        about()
        clear()
    end
    checkHardware()  -- Display hardware issues (and set selected resolution)
    if terminateFlag then return end  -- On hardware error, stop
    redResume()        -- If hardware is ok, restore last redstone channel states
    print("Preparing...")
    if firstRun then    -- Got through checks, don't display about on startup again
        firstRun = false
        saveSettings()
    end
    sleep(.5)
    prtGood("Done!")
    beep(450, .06)
    beep(450, .06)
    sleep(.5)
    clear()
end

function addMenu()  -- Add new menu option
    local item = {}
    clear()
    print(itemInfoPage)
    sleep(.5)
    item[1] = ask("Item title")
    if find(item[1], "%S") then  -- not empty
        item[1] = gsub(item[1], "\n", "")  -- remove the new line at the end
        local ans = ask("channels to control")
        if ans ~= nil then
            for channel in gmatch(ans, "[^,]+") do
                local vals = {}
                vals[1] = tonumber(match(channel, "c(%d+)")) or false
                vals[2] = tonumber(match(channel, "s(%d+)")) or false
                vals[3] = tonumber(match(channel, "p(%d+)")) or false
                if vals[1] and (vals[1] < 1 or vals[1] > 16) then vals[1] = false end
                if vals[2] and (vals[2] < 1 or vals[2] > 6) then vals[2] = false end
                if vals[3] and (vals[3] < 1 or vals[3] > 15) then vals[3] = false end
                if vals[2] then vals[2] = vals[2] - 1 end
                insert(item, vals)    -- Insert value table into item table
            end
            insert(settings, item)    -- Insert new item table into settings table
            saveSettings()    -- Dump settings from memory to disk
            prtWarn("Item created successfully!")
            sleep(1)
        end
    end
end

function remMenu()  -- Remove menu option
    local ans
    clear()
    if #settings == 0 then
        prtBad("Nothing to remove.")
    else
        print("Available options:\n")
        prtOpts(#settings)
        ans = tonumber(ask("\nWhich one would you like to remove?"))
        if ans ~=nil then
            if ans <= 0 or ans > #settings then
                prtBad("Invalid choice.")
            else
                setRedAll(ans, false)
                remove(settings, ans)
                prtWarn("Item removed successfully!")
                saveSettings()
            end
        end
    end
    sleep(1)
end

function redInfo()  -- Print redstone info and channel states/numbers
    clear()
    print(redInfoPage)
    prtColoredMsg("NUM\tCOLOR\t\tSTATE (" .. sideListStr() .. ")", 0xFF00FF)
    prtHR()
    for channel = 1, 16, 1 do
        prtWarn(channel, true)
        write("\t")
        prtColoredColor(redMap(channel))
        write("     \t")
        for ctrlSide = 0, 5, 1 do
            colorState(getRed(redMap(channel), ctrlSide), true)
            if ctrlSide < 5 then write("\t") end
        end
        print()
    end
    color(0xFFFFFF)
    sleep(.5)
    waitEnter(true)
end

function sideInfo()  -- Print available sides and their numbers
    clear()
    print("Available sides:\n")
    for i = 1, 6, 1 do
        print(i .. ". " .. sides[i-1])
    end
    waitEnter(true)
end

function setRes()  -- Change resolution
    local w, h = unpack(resolution)
    local mw, mh = maxResolution()
    clear()
    print("The resolution has to be at least " .. minRes[1] .. "x" .. minRes[2] .. ".")
    print("The resolution has to be at most " .. floor(mw) .. "x" .. floor(mh) .. ".")
    write("Current resolution: ")
    prtWarn(w .. "x" .. h .. "\n")
    w = ask("Width")
    h = ask("Height")
    if w ~= nil and h ~= nil then
        w = tonumber(w)
        h = tonumber(h)
        if w ~= nil and h ~= nil then
            if w >= minRes[1] and h >= minRes[2] and w <= mw and h <= mh then
                if setResolution(w, h) then
                    resolution = pack(getResolution())
                    saveSettings()
                    return
                else
                    prtBad("Failed to set new resolution.")
                end
            end
        end
        prtBad("Invalid choice.")
        sleep(.7)
    end
end

function setSide()  -- Change redstone controlled side
    clear()
    print("From here you can choose which side should be used for redstone control.")
    write("Currently using: [")
    prtWarn(sides[side], true)
    print("]\n")
    ans = ask("\nSide(1-6)")
    if ans ~= nil then
        ans = tonumber(ans)
        if ans ~= nil and ans > 0 and ans < 7 then
            side = ans - 1
            redResume()
            saveSettings()
            prtWarn("Side configured.")
        else
            prtBad("Invalid choice.")
        end
    end
    sleep(.7)
end

function setDefaults()
    passwd = data.sha256("")
    firstRun = true
    dobeep = true
    side = 2
    resolution = {80, 25}
    redState = {}
    settings = {}
    saveSettings()
end

function defaultsPrompt()  -- Replace settings with default ones
    local ans
    clear()
    print("This will restore the default settings!")
    beep(120, .5)
    repeat
        ans = ask("Are you sure you want to proceed (y/n)")
        ans=text.trim(ans ~= nil and ans or "n")
        if ans == "y" then
            clear()
            print("Resetting settings...")
            setDefaults()
            sleep(.3)
            print("Defaults restored!")
            prtWarn("Note: the reset does not disable the service.")
            print("The program will now restart, to apply the changes!")
            sleep(.5)
            waitEnter()
            terminate(true) -- Restart program
            break;
        end
    until ans == "n"
end

function toggleBeep()  -- Toggle beeper
    dobeep=not dobeep
    saveSettings()
    prtWarn("\nBeeper " .. (dobeep and "unmuted" or "muted"))
    beep(400, .04)
    sleep(1.5)
end

function toggleService()  -- Enable/disable service (run on startup)
    local service = rc.loaded["secterm"]
    exec("rc secterm " .. (service and "disable" or "enable"))
    prtWarn("\nService " .. (service and "disabled" or "enabled"))
    beep(400, .04)
    sleep(1.5)
end

function menuPrt()  -- Prints menu, returns number of options (excluding settings & exit)
    clear()
    prtHeader("--- MENU ---\n")
    local settingsIndex = #settings + 1
    local exitIndex = settingsIndex + 1
    prtOpts(exitIndex)
    sleep(.05)
    print(settingsIndex .. ". " .. getPadding(settingsIndex, exitIndex) .. "Settings")
    print(exitIndex .. ". " .. getPadding(exitIndex, exitIndex) .. "Exit\n")
    prtPrompt("Enter your choice: ")
    return #settings
end

function menuInvalid()  -- Print invalid choice error
    prtBad("Invalid choice.", true)
    sleep(.7)
    clearln()
    prtPrompt("Enter your choice: ")
end

function menuSettings()  -- Settings menu
    local func, ans = {
        {about, "About"},
        {redInfo, "Redstone/channel info"},
        {sideInfo, "Side info"},
        {addMenu, "Add menu item"},
        {remMenu, "Remove menu item"},
        {setPW, "Change password"},
        {setSide, "Change default side"},
        {setRes, "Change Resolution"},
        {toggleBeep, (dobeep and "Mute" or "Unmute") .. " beeper"},
        {toggleService, (rc.loaded["secterm"] and "Disable" or "Enable") .. " startup service"},
        {defaultsPrompt, "Restore defaults"},
        {terminate, "Terminate execution"}
    }
    clear()
    prtHeader("--- SETTINGS ---")
    sleep(.4)
    print("What do you want to do?\n")
    local backIndex = #func + 1
    for i = 1, #func, 1 do
        print(i .. ". " .. getPadding(i, backIndex) .. func[i][2])
    end
    print(backIndex .. ". " .. getPadding(backIndex, backIndex) .. "Back\n")
    sleep(.1)
    ans = ask("Enter your choice")
    if ans ~= nil then
        ans = tonumber(ans)
        if ans ~= nil then
            if ans > 0 and ans <= #func then
                func[ans][1]()  -- Exec option
                return
            elseif ans == #func + 1 then  -- Back
                return
            end
        end
        prtBad("Invalid choice.")
        sleep(.7)
    end
end

function onoff(opt)  -- Show component states, ask user for new state
    if not settings[opt] then return end
    clear()
    -- Show states
    print("Current component states:\n")
    for item = 2, #settings[opt], 1 do
        local c = settings[opt][item][1]
        local s = settings[opt][item][2] or side
        local mappedC = redMap(c)
        write("\t")
        prtColoredColor(mappedC)
        write(" (" .. sides[s] .. ")" .. ": ")
        colorState(getRed(mappedC, s))
    end
    sleep(.3)
    -- Show menu
    print("\nWhat do you want to do?\n")
    print("1. Turn ON")
    print("2. Turn OFF")
    print("3. Nothing\n")
    sleep(.1)
    local ans = tonumber(ask("Enter your choice"))
    if ans == 1 or ans == 2 then
        setRedAll(opt, ans == 1)
        saveSettings()
    end
end

function menu()  -- Menu functionality
    local onOffOptNum, ans
    sleep(.2)
    onOffOptNum = menuPrt()
    while true do
        ans = -1
        ans = coloredRead()
        if ans ~= nil then
            ans = tonumber(ans)
            if ans ~= nil then
                if ans <= 0 then
                    menuInvalid()
                elseif ans <= onOffOptNum then        -- On/Off
                    onoff(ans)
                    menuPrt()
                elseif ans == onOffOptNum + 1 then    -- Settings
                    menuSettings()
                    if terminateFlag then break end
                    onOffOptNum = menuPrt()
                elseif ans == onOffOptNum + 2 then    -- Exit
                    sleep(.2)
                    clear()
                    break;
                else
                    menuInvalid()
                end
            else
                menuInvalid()
            end
        else
            break    -- On interrupt
        end
    end
end


--- Main program ---
function main()
    if verifyPW("Password required") then
        prtGood("Access granted.")
        beep(380)
        sleep(.01)
        beep(500)
        sleep(.5)
        menu()    -- Menu
        if terminateFlag then return end
        prtWarn("Exiting...\n")
        beep(500)
        sleep(.01)
        beep(380)
        sleep(.8)
        clear()
    else
        prtBad("Wrong password.\n")
        beep(150)
        sleep(.01)
        beep(150)
    end
    sleep(.2)
end

function errorHandler(err)  -- Log error & traceback
    errLog:write("-------------\n    ERROR\n-------------\n")
    errLog:write(date() .. (err and " - " .. err or "") .. "\n-------------\n")
    errLog:write(traceback() .. "\n\n")
    prtWarn("Dumped traceback to log file.")
end

--- BEGIN ---

init(...)
while not terminateFlag do
    if not xpcall(main, errorHandler) then
        prtBad("Error detected.")
    end
end

--- END ---

setResolution(unpack(nativeRes))  -- Reset resolution
if errLog then errLog:close() end
sleep(.5)
clear()
if restartFlag then
    print("Restarting...")
    exec("secterm")
else
    print("Exited!")
end
exit()

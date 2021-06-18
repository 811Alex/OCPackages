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
local sleep = os.sleep
local write = io.write
local open = io.open
local pack = table.pack
local unpack = table.unpack
local insert = table.insert
local remove = table.remove
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
local terminateFlag = false  -- terminate execution of main program
local restartFlag = false    -- restart after termination
local errLog
local settings
local redState
local resolution
local side
local dobeep
local passwd
local firstRun
local multiSide
-- Const
local settingsFile = "/etc/secterm.conf"
local rcFile = "/etc/rc.d/secterm.lua"
local logDir = "/var/log"
local logFile = logDir .. "/secterm.log"
local minRes = {80,25}
local nativeRes = pack(gpu.getResolution())
local helpPage = [[
        --- About SecTerm ---

This program was initially developed by Alex811.
The files used by this program are licenced under the MIT license (Expat).
You may use, distribute, modify, etc. this program as you see fit,
but I would appreciate it if you gave me appropriate credit.

Please keep in mind the following:
  This program is designed to run on OpenComputers with:
    a tier 2 or higher GPU,
    a tier 2 or higher screen,
    a tier 2 redstone card,
    a tier 1 or higher data card,
    enough memory.
  This program is designed to be used with ProjectRed Bundled Cables.
  It might work fine with RedPower2 or even EnderIO Redstone Conduits in some versions.
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
You can create/delete the items of the menu through the settings.
Each item controls one or more ProjectRed Bundled Cable channel (color).
The channels have to be specified using their numbers,
take a look at "Redstone info" for more info.
To specify more than one channel, write all the channel numbers,
separated with spaces, when entering those.
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
    return fmod((31 - n),16)
end

function colorState(b)  -- Print a green "ON" or a red "OFF" according to the argument
    if b then
        prtGood("ON")
    else
        prtBad("OFF")
    end
end

function terminate()  -- Terminate execution
    terminateFlag = true
    prtWarn("Terminating execution...")
    beep(500)
    beep(120, .3)
end

function loadSettings()  -- Load settings file into memory
    local file = open(settingsFile, "r")
    passwd = data.decode64(file:read("*l"))
    firstRun = unserialize(file:read("*l"))
    dobeep = unserialize(file:read("*l"))
    multiSide = unserialize(file:read("*l"))
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
    file:write(serialize(multiSide) .. "\n")
    file:write(serialize(side) .. "\n")
    file:write(serialize(resolution) .. "\n")
    file:write(serialize(redState) .. "\n")
    file:write(serialize(settings) .. "\n")
    file:close()
    prtWarn("Settings saved!")
end

function prtGood(msg)
    color(0x00FF00)
    print(msg)
    color(0xFFFFFF)
end

function prtWarn(msg)
    color(0xFFFF00)
    print(msg)
    color(0xFFFFFF)
end

function prtBad(msg)
    color(0xFF0000)
    print(msg)
    color(0xFFFFFF)
end

function prtPrompt(msg)
    color(0x99B2F2)
    write(msg)
    color(0xFFFFFF)
end

function prtHeader(msg)
    color(0x0000FF)
    print(msg)
    color(0xFFFFFF)
end

function prtOpts(maxNum4Padding)  -- Print available options added by the user
    for i = 1, #settings, 1 do
        sleep(.05)
        write(i .. ". " .. getPadding(i, maxNum4Padding) .. settings[i][1])
    end
end

function ask(prompt)
    prtPrompt(prompt .. ": ")
    return read()
end

function waitEnter(--[[optional]]startWithNL)
    prtPrompt((startWithNL and "\n" or "") .. "Press Enter to continue...")
    read()
end

function askSide()  -- Ask user for a side to control, after printing the options, returns the side number
    print("Available sides:")
    for i = 1, 6, 1 do
        print("\t" .. i .. ". " .. sides[i-1])
    end
    ans = ask("\nSide(1-6)")
    if ans ~= nil then
        ans = tonumber(ans)
        if ans ~= nil and ans > 0 and ans < 7 then
            return ans - 1
        else
            prtBad("Invalid choice.")
            return false
        end
    end
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
    color(0xFFAA00)
    local input = read({}, false, {}, "*")
    color(0xFFFFFF)
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

function getRed(obj)  -- Get digital redstone signal
    return (redstone.getBundledOutput(side, obj) > 0)
end

function setRed(obj, ctrSide, stateArg)  -- Set digital redstone signal
    local state = stateArg * 15
    if getRed(obj) ~= (stateArg > 0) then    -- If requested state is different than current
        redstone.setBundledOutput(ctrSide, obj, state)    -- Set state
        redState[obj + 1] = stateArg    -- Save state to memory
        beep(stateArg > 0 and 520 or 420, .04)
    end
end

function redResume()  -- Set redstone states from memory
    print("Restoring redstone states...")
    for i = 1, 16, 1 do
        setRed(i - 1, redState[i])
    end
end

function checkHardware()  -- Test hardware compatibility and display errors (also tries to set the selected resolution)
    local w, h = gpu.maxResolution()
    print("Checking hardware...")
    if w >= resolution[1] and h >= resolution[2] then
        if gpu.setResolution(unpack(resolution)) or serialize(pack(gpu.getResolution())) == serialize(resolution) then
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
    local t, j, ans = {}
    clear()
    t[1] = ask("Item title")
    local tmpSide = multiSide and askSide() or side
    if not tmpSide then
        prtBad("Invalid side, aborting.")
    else
        t[2] = tmpSide
        ans = ask("channels to control")
        if ans ~= nil then
            for i in string.gmatch(ans, "%S+") do    -- Split channels
                j = tonumber(i)
                if j == nil then
                    prtBad("Invalid input, aborting.")
                    sleep(0.8)
                    return
                end
                insert(t, j)    -- And insert them in the new table
            end
            insert(settings, t)    -- Insert new table into settings table
            prtWarn("Item created successfully!")
            sleep(0.3)
            saveSettings()    -- Dump settings from memory to disk
        else
            prtBad("Invalid input, aborting.")
        end
    end
    sleep(0.7)
end

function remMenu()  -- Remove menu option
    local ans
    clear()
    if #settings == 0 then
        prtBad("Nothing to remove.")
    else
        print("Available options:\n")
        prtOpts(#settings)
        repeat
            ans = tonumber(ask("\nWhich one would you like to remove? (0 to abort)"))
            if ans ~=nil then
                if ans < 0 or ans > #settings then
                    prtBad("Invalid choice.")
                elseif ans > 0 then
                    remove(settings, ans)
                    prtWarn("Item removed successfully!")
                    saveSettings()
                    sleep(1)
                    break
                end
            end
        until ans == 0
    end
end

function redInfo()  -- Print redstone info and channel states
    clear()
    print(redInfoPage)
    color(0xFF00FF)
    print("NUM\tCOLOR\t\tSTATE")
    color(0x0000FF)
    print("------------------------------")
    for i = 1, 16, 1 do
        color(0xFFFF00)
        write(i)
        color(0xFFFFFF)
        write("\t" .. colors[redMap(i)] .. "     \t")
        colorState(getRed(redMap(i)))
    end
    color(0xFFFFFF)
    sleep(.5)
    waitEnter(true)
end

function itemInfo()   -- Print info
    clear()
    prtHeader("--- Item info ---\n")
    print(itemInfoPage)
    sleep(.5)
    waitEnter(true)
end

function setRes()  -- Change resolution
    local w, h = unpack(resolution)
    local mw, mh = gpu.maxResolution()
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
            if w > minRes[1] and h > minRes[2] and w <= mw and h <= mh then
                if gpu.setResolution(w, h) then
                    resolution = pack(gpu.getResolution())
                    saveSettings()
                    return
                end
            end
        end
        prtBad("Invalid choice.")
        sleep(.7)
    end
end

function setSide()  -- Change redstone controlled side
    local ans
    clear()
    print("From here you can choose which side should be used for redstone control.")
    if multiSide then
        prtWarn("This option is not available in multi-side mode!")
        beep(150)
        sleep(2)
        beep(150)
        return
    end
    write("Currently using: [")
    color(0xFFFF00)
    write(sides[side])
    color(0xFFFFFF)
    print("]\n\n")
    local tmpSide = askSide()
    if tmpSide then
        side = tmpSide
        redResume()
        saveSettings()
        prtWarn("Side configured.")
    end
    sleep(.7)
end

function setDefaults()
    passwd = data.sha256("")
    firstRun = true
    dobeep = true
    side = 2
    resolution = {80, 25}
    redState = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
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
            terminate() -- Restart program
            restartFlag = true
            break;
        end
    until ans == "n"
end

function toggleMultiSide()  -- Toggle multi-side mode
    multiSide=not multiSide
    saveSettings()
    prtWarn("\nMulti-side mode " .. (multiSide and "enabled" or "disabled"))
    beep(400, .04)
    sleep(1.5)
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
    prtBad("Invalid choice.")
    sleep(.7)
    clearln()
    term.setCursor(1, select(2, term.getCursor()) - 1)
    clearln()
    prtPrompt("Enter your choice: ")
end

function menuSettings()  -- Settings menu
    local func, ans = {
        {about, "About"},
        {setPW, "Change password"},
        {redInfo, "Redstone info"},
        {itemInfo, "About menu items"},
        {addMenu, "Add menu item"},
        {remMenu, "Remove menu item"},
        {setSide, "Change side"},
        {setRes, "Change Resolution"},
        {toggleMultiSide, (multiSide and "Disable" or "Enable") .. " multi-side mode"},
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
    local obj, ans
    clear()
    -- Show states
    if #settings[opt] == 3 then
        obj = redMap(settings[opt][3])
        write("This component (" .. colors[obj] .. ") is currently ")
        colorState(getRed(obj))
    else
        print("These components are currently:")
        for j = 3, #settings[opt], 1 do
            obj = redMap(settings[opt][j])
            write("\t(" .. colors[obj] .. ")    \t")
            colorState(getRed(obj))
        end
    end
    sleep(.3)
    -- Show menu
    print("\nWhat do you want to do?\n")
    print("1. Turn ON")
    print("2. Turn OFF")
    print("3. Nothing")
    sleep(.1)
    ans = tonumber(ask("Enter your choice"))
    if ans == 1 or ans == 2 then
        ans = fmod(ans, 2)
        for j = 3, #settings[opt], 1 do
            obj = redMap(settings[opt][j])
            setRed(obj, settings[opt][2], ans)
        end
        saveSettings()
    end
end

function menu()  -- Menu functionality
    local onOffOptNum, ans
    sleep(.2)
    onOffOptNum = menuPrt()
    while true do
        ans = -1
        ans = read()
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

gpu.setResolution(unpack(nativeRes))  -- Reset resolution
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

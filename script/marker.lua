local vkeys = require 'vkeys'
local sampev = require 'lib.samp.events'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local inicfg = require 'inicfg'
local memory = require 'memory'

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local ffi = require 'ffi'
ffi.cdef [[
short GetAsyncKeyState(int vKey);
]]

local function isRawKeyDown(vkey)
    local state = ffi.C.GetAsyncKeyState(vkey)
    return bit.band(state, 0x8000) ~= 0
end

-- Переменная для анти-флуда (чтобы не спамило метками)
local lastActionTime = 0

-- ФАЙЛ НАСТРОЕК
local default_config = {
    settings = {
        activationKey = 78,
        activationMod = 0,
        myPosKey = 88,
        myPosMod = 0,
        mapShiftKey = 16,
        mapShiftMod = 0,
        deleteInGameKey = 188,
        deleteInGameMod = 0,
        deleteMapKey = 74,
        deleteMapMod = 0,
        deleteOldKey = 51,
        deleteOldMod = 0,
        deleteLastKey = 52,
        deleteLastMod = 0,
        chaseKey = 0,
        chaseMod = 0,
        deleteChaseKey = 0,
        deleteChaseMod = 0
    }
}

-- В таблицу меток добавим суффиксы для удобства поиска
local keyLabels = {{
    name = "Поставить метку (Мир)",
    var = "activation"
}, {
    name = "Метка под себя",
    var = "myPos"
}, {
    name = "Удалить метку в мире",
    var = "deleteInGame"
}, {
    name = "Удалить ВСЕ метки карты",
    var = "deleteMap"
}, {
    name = "Удалить СТАРУЮ метку карты",
    var = "deleteOld"
}, {
    name = "Удалить НОВУЮ метку карты",
    var = "deleteLast"
}, {
    name = "Погоня",
    var = "chase"
}, {
    name = "Удалить погоню",
    var = "deleteChase"
} -- Добавили это
}

local config_data = inicfg.load(default_config, direct) or default_config

-- ПЕРЕМЕННЫЕ
local showMenu = imgui.new.bool(false)
local editKeyIndex = 0
local markLabels = {"1", "2", "3", "4", "5", "6", "7"} -- Тексты по умолчанию
local chatCommand = "/fc"
local myWorld3D, car3D, myCarBlip, myWorldBlip = nil, nil, nil , nil
local myMapMarkers = {}
local remoteMarkers = {}
local pressState = {}
local my_font = nil
local waypoint_img, map_waypoint_img = nil, nil
local menuWasOpen = false
local lastMapActionTime = 0
local mapShiftWasDown = false

local TIMER_WORLD, TIMER_MAP, MAX_MAP_MARKERS = 120, 1800, 7

-- ФУНКЦИИ
function isKeyComboPressed(key, mod)
    local k = tonumber(key) or 0
    local m = tonumber(mod) or 0
    if k == 0 then
        return false
    end

    local id = string.format("%d_%d", k, m)
    local isDown = false

    if m ~= 0 then
        -- Если это сочетание (Shift + X): обе кнопки должны быть зажаты
        isDown = isKeyDown(m) and isKeyDown(k)
    else
        -- Если это одиночная клавиша (X): кнопка зажата, а моды — НЕТ
        local anyMod = isKeyDown(16) or isKeyDown(17) or isKeyDown(18)
        isDown = isKeyDown(k) and not anyMod
    end

    -- "Защелка" (чтобы срабатывало 1 раз)
    if isDown then
        if not pressState[id] then
            pressState[id] = true
            return true
        end
    else
        pressState[id] = false
    end
    return false
end

function draw3DRender(x, y, z, label, color, texture)
    local sx, sy = convert3DCoordsToScreen(x, y, z)
    local _, _, _, onScreen = convert3DCoordsToScreenEx(x, y, z)
    
    if onScreen > 0 then
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local dist = getDistanceBetweenCoords3d(px, py, pz, x, y, z)
        
        -- 1. Рисуем иконку (центрируем саму иконку 24x24)
        if texture and texture ~= 0 then 
            renderDrawTexture(texture, sx - 12, sy - 12, 24, 24, 0, color)
        else 
            renderFontDrawText(my_font, "V", sx - 5, sy - 20, color) 
        end

        -- 2. Готовим чистый текст
        local cleanLabel = tostring(label or ""):gsub("[%[%]%(%)]", ""):gsub("none", "")
        cleanLabel = cleanLabel:match("^%s*(.-)%s*$") or ""
        local footer = string.format("%s [%.0fm]", cleanLabel, dist)

        -- 3. ЦЕНТРИРОВАНИЕ ПО ГОРИЗОНТАЛИ
        -- Вычисляем ширину текста, чтобы знать, сколько отнять от центра
        local textWidth = renderGetFontDrawTextLength(my_font, footer)
        local posX = sx - (textWidth / 2) -- Вычитаем половину ширины
        local posY = sy + 15              -- Смещение вниз под иконку

        renderFontDrawText(my_font, footer, posX, posY, 0xFFFFFFFF)
    end
end

function getMapScreenCoords(x, y)
    -- Используем чтение памяти через memory для стабильности
    local ptr = memory.read(0xBA6748, 4, false)
    if ptr == 0 then
        return nil, nil
    end

    -- Проверка, что мы именно в меню карты
    local inMap = memory.read(0xBA67A4 + 1, 1, false)
    if inMap ~= 3 then
        return nil, nil
    end

    local mult_x = memory.getfloat(ptr + 0x860)
    local mult_y = memory.getfloat(ptr + 0x864)
    local map_x = memory.getfloat(ptr + 0x868)
    local map_y = memory.getfloat(ptr + 0x86C)

    -- Если данные «нулевые» (меню еще грузится) — выходим
    if mult_x == 0 then
        return nil, nil
    end

    return map_x + (x * mult_x), map_y - (y * mult_y)
end

function getTargetPoint()
    local camX, camY, camZ = getActiveCameraCoordinates()
    local tarX, tarY, tarZ = getActiveCameraPointAt()
    local vecX, vecY, vecZ = (tarX - camX) * 300, (tarY - camY) * 300, (tarZ - camZ) * 300
    local res, col = processLineOfSight(camX, camY, camZ, camX + vecX, camY + vecY, camZ + vecZ, true, false, false,
        true, false, false, false)
    if res and col.pos then
        return col.pos[1], col.pos[2], col.pos[3]
    end
    return nil
end

-- ОТРИСОВКА МЕНЮ
imgui.OnFrame(function()
    return showMenu[0]
end, function(player)
    player.LockPlayer = true
    imgui.SetNextWindowSize(imgui.ImVec2(450, 350), imgui.Cond.FirstUseEver)
    if imgui.Begin(u8 "Настройки HRT", showMenu, imgui.WindowFlags.NoCollapse) then
        imgui.Text(u8 "Настройки клавиш:")
        imgui.Separator()

        for i, item in ipairs(keyLabels) do
            local kId = tonumber(config_data.settings[item.var .. "Key"]) or 0
            local mId = tonumber(config_data.settings[item.var .. "Mod"]) or 0

            local keyName = (kId > 0) and (vkeys.id_to_name(kId) or "ID:" .. kId) or "NONE"
            local modName = (mId > 0) and (vkeys.id_to_name(mId) .. " + ") or ""
            local btnText = (editKeyIndex == i) and u8 "???" or u8(modName .. keyName)

            imgui.Text(u8(item.name))
            imgui.SameLine(250)
            if imgui.Button(btnText .. "##" .. i, imgui.ImVec2(180, 25)) then
                editKeyIndex = i
            end
        end

        if imgui.Button(u8 "Закрыть (ESC)", imgui.ImVec2(-1, 30)) then
            showMenu[0] = false
        end
        imgui.End()
    end
end)

function onWindowMessage(msg, wparam, lparam)
    if msg == 0x0100 and wparam == 0x1B and showMenu[0] then
        showMenu[0] = false
        consumeWindowMessage(msg, true)
    end
end

local function sendMapMark(idx, x, y, label)
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local myName = sampGetPlayerNickname(myId)
    local txt = (label and label:gsub("%s+", "") ~= "") and label or "none"
    
    -- Формат: !MAPMARK:Ник:X:Y:Индекс:Тип:Текст (Всего 6 полей)
    local msg = string.format("%s !MAPMARK:%s:%.1f:%.1f:%d:std:%s", 
        chatCommand, myName, x, y, idx, txt)
    sampSendChat(msg)
end

function main()
    local lastPressTime = 0
    local capturedKey, capturedMod = 0, 0
    local isWaitingRelease = false

    while not isSampAvailable() do
        wait(100)
    end
    sampAddChatMessage("{00fc76}[HRT] {FFFFFF}Скрипт загружен. Пропишите /spoint", -1)
    my_font = renderCreateFont('Arial', 10, 5)

    if doesFileExist('moonloader/markerlib/images/radar_waypoint.png') then
        waypoint_img = renderLoadTextureFromFile('moonloader/markerlib/images/radar_waypoint.png')
    end
    if doesFileExist('moonloader/markerlib/images/map_waypoint.png') then
        map_waypoint_img = renderLoadTextureFromFile('moonloader/markerlib/images/map_waypoint.png')
    end
    if doesFileExist('moonloader/markerlib/images/car.png') then
        icon_car = renderLoadTextureFromFile('moonloader/markerlib/images/car.png')
    end

    sampRegisterChatCommand("spoint", function()
        showMenu[0] = not showMenu[0]
    end)

    while true do
        wait(0)
        local currentTime = os.clock()
        local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local myName = sampGetPlayerNickname(myId)


        for rName, pData in pairs(remoteMarkers) do
            -- Таймер для SQUAD и CHASE (2 минуты = 120 секунд)
            if pData.world and (currentTime - pData.world.time) > 120 then
                if pData.world.blip then removeBlip(pData.world.blip) end
                pData.world = nil
            end

            -- Таймер для меток с карты (30 минут = 1800 секунд)
            if pData.map then
                for i, m in pairs(pData.map) do
                    if (currentTime - m.time) > 1800 then
                        if m.blip then removeBlip(m.blip) end
                        pData.map[i] = nil
                    end
                end
            end
        end

        if myWorld3D and myWorldTime and (currentTime - myWorldTime) > 120 then
            if myWorldBlip then removeBlip(myWorldBlip); myWorldBlip = nil end
            myWorld3D = nil
            printStringNow("~r~Time OUT Marker ~w~", 2000)
        end

        -- Таймер для своей погони (CHASE)
        if car3D and (currentTime - car3D.time) > 120 then
            if myCarBlip then
                removeBlip(myCarBlip)
                myCarBlip = nil
            end
            car3D = nil
        end

        -- Твои метки на карте (30 мин)
        for i, m in pairs(myMapMarkers) do
            if m.time and (currentTime - m.time) > 1800 then
                if m.blip then removeBlip(m.blip) end
                table.remove(myMapMarkers, i)
                printStringNow("~r~Time OUT Map Marker ~w~", 2000)
            end
        end

        local shiftPressed = bit.band(ffi.C.GetAsyncKeyState(0x10), 0x8000) ~= 0
        -- ЛОГИКА ДЛЯ КАРТЫ (SHIFT)
        if isPauseMenuActive() then
            if shiftPressed and not mapShiftWasDown then

                local currentTime = os.clock()
                if currentTime - lastMapActionTime > 0.5 then
                    local result, mx, my, finalZ = getTargetBlipCoordinates()

                    if result then
                        if #myMapMarkers >= MAX_MAP_MARKERS then
                            if myMapMarkers[1].blip then
                                removeBlip(myMapMarkers[1].blip)
                            end
                            table.remove(myMapMarkers, 1)
                        end

                        local newBlip = addBlipForCoord(mx, my, finalZ)
                        local currentIdx = #myMapMarkers + 1

                        if newBlip then
                            table.insert(myMapMarkers, {
                                x = mx,
                                y = my,
                                z = finalZ,
                                blip = newBlip,
                                creator = myName,
                                label = " ",
                                time = currentTime
                            })

                            sendMapMark(currentIdx, mx, my, " ")
                            printStringNow("~g~MARK #" .. currentIdx .. " SET", 1000)
                        end

                        lastMapActionTime = currentTime
                    end
                end
            end

            mapShiftWasDown = shiftPressed


            if mapPtr ~= 0 and inMapPage then
                -- Твои метки
                for i, m in ipairs(myMapMarkers) do
                    local sx, sy = getMapScreenCoords(m.x, m.y)
                    if sx and sy and sx > 0 then
                        renderFontDrawText(my_font, string.format("%s [%d]", m.creator or myName, i), sx - 20, sy + 10,
                            0xFFFFFFFF)
                    end
                end

                -- Метки чужих игроков
                for rName, pData in pairs(remoteMarkers) do
                    if pData.map then
                        for i, m in ipairs(pData.map) do
                            local tag = m.label or tostring(i)
                            local display = string.format("%s [%s]", rName, tag)

                            draw3DRender(m.x, m.y, m.z, display, 0xFF4BCCFF, map_waypoint_img or waypoint_img)
                        end
                    end
                end
            end
        end

        if showMenu[0] then
            menuWasOpen = true
            sampSetCursorMode(2)

            -- ЗАХВАТ КЛАВИШ
            if editKeyIndex ~= 0 then
                if not isWaitingRelease then
                    -- 1. Постоянно проверяем, зажат ли какой-то модификатор сейчас
                    local currentMod = 0
                    if isKeyDown(16) or isKeyDown(160) or isKeyDown(161) then
                        currentMod = 16
                    elseif isKeyDown(17) or isKeyDown(162) or isKeyDown(163) then
                        currentMod = 17
                    elseif isKeyDown(18) or isKeyDown(164) or isKeyDown(165) then
                        currentMod = 18
                    end

                    -- 2. Ищем нажатие основной (не системной) клавиши
                    for v = 0, 255 do
                        if isKeyDown(v) then
                            -- Проверяем, является ли нажатая кнопка модификатором
                            local isMod = (v == 16 or v == 17 or v == 18 or (v >= 160 and v <= 165))

                            if not isMod then
                                -- Если нажали ОБЫЧНУЮ кнопку (X, F2, 5 и т.д.)
                                capturedKey = v
                                capturedMod = currentMod -- Записываем тот мод, что был зажат в этот момент
                                isWaitingRelease = true
                                break
                            end
                            -- Если нажали ТОЛЬКО Shift/Alt/Ctrl — ничего не делаем, ждем дальше
                        end
                    end
                else
                    -- Ждем отпускания всех кнопок
                    local anyDown = false
                    for v = 0, 255 do
                        if isKeyDown(v) then
                            anyDown = true
                            break
                        end
                    end
                    if not anyDown then
                        local varBase = keyLabels[editKeyIndex].var
                        config_data.settings[varBase .. "Key"] = capturedKey
                        config_data.settings[varBase .. "Mod"] = capturedMod
                        inicfg.save(config_data, direct)

                        local keyName = vkeys.id_to_name(capturedKey) or "ID:" .. capturedKey
                        local modName = (capturedMod ~= 0 and (vkeys.id_to_name(capturedMod) .. " + ") or "")
                        sampAddChatMessage("{00fc76}[HRT] {FFFFFF}Сохранено: " .. modName .. keyName, -1)

                        editKeyIndex, isWaitingRelease, capturedKey, capturedMod = 0, false, 0, 0
                    end
                end
            end

        elseif menuWasOpen then
            sampSetCursorMode(0)
            menuWasOpen = false
        end

        -- ЛОГИКА В ИГРЕ
        -- В ИГРЕ (ГОРЯЧИЕ КЛАВИШИ)
        if not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() and not showMenu[0] then

            local s = config_data.settings -- для краткости кода

            -- 1. Поставить метку (Мир)
            if isKeyComboPressed(s.activationKey, s.activationMod) then
                local x, y, z = getTargetPoint()
                local px, py, pz = getCharCoordinates(PLAYER_PED)
                if x then
                    if myWorldBlip then
                        removeBlip(myWorldBlip)
                    end
                    myWorld3D = {
                        x = x,
                        y = y,
                        z = z,
                        time = currentTime
                    }
                    myWorldTime = currentTime -- ВАЖНО!
                    myWorldBlip = addBlipForCoord(x, y, z)
                    sampSendChat(string.format("%s !SQUAD:%s:%.1f:%.1f:%.1f", chatCommand, myName, x, y, z))
                end
            end

            -- Погоня (Аналог кнопки N)
            if isKeyComboPressed(s.chaseKey, s.chaseMod) then
                local x, y, z = getTargetPoint()
                if x then
                    if myCarBlip then
                        removeBlip(myCarBlip)
                    end
                    car3D = {
                        x = x,
                        y = y,
                        z = z,
                        time = currentTime
                    }
                    myCarBlip = addBlipForCoord(x, y, z)
                    sampSendChat(string.format("%s !CHASE:%s:%.1f:%.1f:%.1f", chatCommand, myName, x, y, z))
                    printStringNow("~r~CHASE STARTED", 1000)
                end
            end

            -- 2. Метка под себя
            if isKeyComboPressed(s.myPosKey, s.myPosMod) then
                local x, y, z = getCharCoordinates(PLAYER_PED)
                if myWorldBlip then
                    removeBlip(myWorldBlip)
                end
                myWorld3D = {
                    x = x,
                    y = y,
                    z = z,
                    time = currentTime
                }
                myWorldTime = currentTime -- ВАЖНО!
                myWorldBlip = addBlipForCoord(x, y, z)
                sampSendChat(string.format("%s !SQUAD:%s:%.1f:%.1f:%.1f", chatCommand, myName, x, y, z))
            end

            -- 3. Удалить старую метку карты
            if isKeyComboPressed(s.deleteOldKey, s.deleteOldMod) and #myMapMarkers > 0 then
                if myMapMarkers[1].blip then
                    removeBlip(myMapMarkers[1].blip)
                end
                table.remove(myMapMarkers, 1)
                sampSendChat(string.format("%s !MAP_REMOVE_OLD:%s", chatCommand, myName))
                printStringNow("~y~OLD MARK REMOVED", 1000)
            end

            -- 4. Удалить новую метку карты
            if isKeyComboPressed(s.deleteLastKey, s.deleteLastMod) and #myMapMarkers > 0 then
                local idx = #myMapMarkers
                if myMapMarkers[idx].blip then
                    removeBlip(myMapMarkers[idx].blip)
                end
                table.remove(myMapMarkers, idx)
                sampSendChat(string.format("%s !MAP_REMOVE_LAST:%s", chatCommand, myName))
                printStringNow("~r~NEW MARK REMOVED", 1000)

            end

            -- 5. Удалить метку в мире
            if isKeyComboPressed(s.deleteInGameKey, s.deleteInGameMod) and myWorld3D then
                myWorld3D = nil
                if myWorldBlip then
                    removeBlip(myWorldBlip)
                    myWorldBlip = nil
                end
                sampSendChat(string.format("%s !SQUAD_CLEAR:%s", chatCommand, myName))
                printStringNow("~r~MARK REMOVED", 1000)

            end

            -- 6. Удалить ВСЕ метки карты
            if isKeyComboPressed(s.deleteMapKey, s.deleteMapMod) and #myMapMarkers > 0 then
                for _, m in ipairs(myMapMarkers) do
                    if m.blip then
                        removeBlip(m.blip)
                    end
                end
                myMapMarkers = {}
                sampSendChat(string.format("%s !MAPMARK_CLEAR:%s", chatCommand, myName))
                printStringNow("~y~ALL MAP MARKS REMOVED", 1000)
            end

            -- Удалить метку погони
            if isKeyComboPressed(s.deleteChaseKey, s.deleteChaseMod) and car3D then
                car3D = nil
                if myCarBlip then
                    removeBlip(myCarBlip)
                    myCarBlip = nil
                end
                -- Отправляем в чат, чтобы у других тоже стерлось (опционально)
                sampSendChat(string.format("%s !CHASE_CLEAR:%s", chatCommand, myName))
                printStringNow("~r~CHASE MARK REMOVED", 1000)
            end
        end

        -- ОТДЕЛЬНО ДЛЯ КАРТЫ (внутри цикла while true)
        if not isPauseMenuActive() then
            -- Твоя основная цель
            if myWorld3D then
                draw3DRender(myWorld3D.x, myWorld3D.y, myWorld3D.z, "ЦЕЛЬ", 0xFFFF4B4B, waypoint_img)
            end

            -- Твоя погоня
            if car3D then
                draw3DRender(car3D.x, car3D.y, car3D.z, "ПОГОНЯ", 0xFFFF4B4B, icon_car)
            end

            -- Твои метки на карте
            for i, m in ipairs(myMapMarkers) do
                draw3DRender(m.x, m.y, m.z, "МЕТКА " .. i, 0xFFFF4B4B, map_waypoint_img or waypoint_img)
            end

            -- Метки от других игроков
            for rName, pData in pairs(remoteMarkers) do
                if pData.world then
                    -- Если это погоня, рисуем машину, иначе стрелку
                    local tex = pData.world.isChase and icon_car or waypoint_img
                    local label = pData.world.isChase and rName .. " [Погоня]" or rName
                    draw3DRender(pData.world.x, pData.world.y, pData.world.z, label, 0xFF4BCCFF, tex)
                end
                if pData.map then
                    for i, m in ipairs(pData.map) do
                        -- Если у метки есть свой label, пишем его, если нет - пишем номер
                        local tag = m.label or tostring(i)
                        local display = string.format("%s [%s]", rName, tag)

                        draw3DRender(m.x, m.y, m.z, display, 0xFF4BCCFF, map_waypoint_img or waypoint_img)
                    end
                end
            end
        end
    end
end

function sampev.onServerMessage(color, text)
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local myName = sampGetPlayerNickname(myId)
    local currentTime = os.clock()

   -- 1. Обработка SQUAD (обычная метка)
    if text:find("!SQUAD:") then
        -- Шаблон: Имя(1) : X(2) : Y(3) : Z(4)
        local name, x, y, z = text:match("!SQUAD:(.+):(.+):(.+):(.+)")
        if name and name ~= myName then
            if not remoteMarkers[name] then remoteMarkers[name] = { map = {} } end
            if remoteMarkers[name].world and remoteMarkers[name].world.blip then removeBlip(remoteMarkers[name].world.blip) end
            
            local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
            remoteMarkers[name].world = {
                x = nx, y = ny, z = nz, 
                isChase = false,
                time = os.clock(),
                blip = addBlipForCoord(nx, ny, nz)
            }
        end

    -- 2. Обработка ПОГОНИ (CHASE)
    elseif text:find("!CHASE:") then
        -- Шаблон: Имя(1) : X(2) : Y(3) : Z(4)
        local name, x, y, z = text:match("!CHASE:(.+):(.+):(.+):(.+)")
        if name and name ~= myName then
            if not remoteMarkers[name] then remoteMarkers[name] = { map = {} } end
            if remoteMarkers[name].world and remoteMarkers[name].world.blip then removeBlip(remoteMarkers[name].world.blip) end
            
            local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
            remoteMarkers[name].world = {
                x = nx, y = ny, z = nz, 
                isChase = true,
                time = os.clock(),
                blip = addBlipForCoord(nx, ny, nz)
            }
            printStringNow("~r~CHASE STARTED BY ~w~" .. name, 2000)
        end

    -- 3. Метки карты (MAPMARK)
    elseif text:find("!MAPMARK:") then
        -- Старый добрый шаблон на 6 параметров (без Z)
        local name, x, y, idx, mType, label = text:match("!MAPMARK:(.+):(.+):(.+):(%d+):(.+):(.+)")
        
        if name and name ~= myName and x and y then
            if not remoteMarkers[name] then remoteMarkers[name] = { map = {} } end
            local i = tonumber(idx)

            if remoteMarkers[name].map[i] and remoteMarkers[name].map[i].blip then
                removeBlip(remoteMarkers[name].map[i].blip)
            end

            remoteMarkers[name].map[i] = {
                x = tonumber(x),
                y = tonumber(y),
                z = 10.0, -- Возвращаем стандартную высоту, раз Z не передаем
                label = (label ~= "none") and label or nil,
                blip = addBlipForCoord(tonumber(x), tonumber(y), 5.0),
                time = os.clock()
            }
        end

     -- Удаление СТАРОЙ (первой) метки
    elseif text:find("!MAP_REMOVE_OLD:") then
        local name = text:match("!MAP_REMOVE_OLD:(%S+)")
        if name and remoteMarkers[name] and remoteMarkers[name].map then
            -- Проверяем наличие первой метки (индекс 1)
            if remoteMarkers[name].map[1] then
                if remoteMarkers[name].map[1].blip then
                    removeBlip(remoteMarkers[name].map[1].blip)
                end
                table.remove(remoteMarkers[name].map, 1)
            end
        end

    -- Удаление ПОСЛЕДНЕЙ метки
    elseif text:find("!MAP_REMOVE_LAST:") then
        local name = text:match("!MAP_REMOVE_LAST:(%S+)")
        if name and remoteMarkers[name] and remoteMarkers[name].map then
            local count = #remoteMarkers[name].map
            if count > 0 then
                if remoteMarkers[name].map[count].blip then
                    removeBlip(remoteMarkers[name].map[count].blip)
                end
                table.remove(remoteMarkers[name].map, count)
            end
        end

    -- Очистка обычной метки (SQUAD)
    elseif text:find("!SQUAD_CLEAR:") then
        local name = text:match("!SQUAD_CLEAR:(%S+)")
        if name then
            if remoteMarkers[name] and remoteMarkers[name].world then
                if remoteMarkers[name].world.blip then
                    removeBlip(remoteMarkers[name].world.blip)
                end
                remoteMarkers[name].world = nil
            end
        end

    -- Очистка погони (CHASE)
    elseif text:find("!CHASE_CLEAR:") then
        local name = text:match("!CHASE_CLEAR:(%S+)")
        if name then
            if remoteMarkers[name] and remoteMarkers[name].world then
                if remoteMarkers[name].world.blip then
                    removeBlip(remoteMarkers[name].world.blip)
                end
                remoteMarkers[name].world = nil
            end
        end

        -- Очистка всех меток карты (MAPMARK)
    elseif text:find("!MAPMARK_CLEAR:") then
        local name = text:match("!MAPMARK_CLEAR:(%S+)")
        if name then
            if not remoteMarkers[name] then
                remoteMarkers[name] = { map = {} }
            end

            if not remoteMarkers[name].map then
                remoteMarkers[name].map = {}
            end

            for _, m in ipairs(remoteMarkers[name].map) do
                if m.blip then
                    removeBlip(m.blip)
                end
            end

            remoteMarkers[name].map = {}
        end
    end

    if text:find("!%u+:%S+") then
        return false
    end
end

sampRegisterChatCommand("mtext", function(arg)
    local idx, text = arg:match("(%d+)%s+(.+)")
    local i = tonumber(idx)

    if i and myMapMarkers[i] and text then
        local cleanText = text:sub(1, 5)
        myMapMarkers[i].label = cleanText

        -- Отправляем те же координаты, тот же индекс, но НОВЫЙ текст
        sendMapMark(i, myMapMarkers[i].x, myMapMarkers[i].y, cleanText)

        sampAddChatMessage("{00fc76}[HRT] {FFFFFF}Метке #" .. i .. " присвоен текст: " .. cleanText,
            -1)
    else
        sampAddChatMessage("{00fc76}[HRT] {FFFFFF}Пример: /mtext 1 БАЗА", -1)
    end
end)
local Radio = require("radio.lua")
local shouldDraw = false

registerForEvent("onInit", function()
    Radio:Init()
end)

registerForEvent("onShutdown", function()
    sinceUpdate = 0
    shouldDraw = false
end)

registerForEvent("onOverlayOpen", function()
    shouldDraw = true
end)

registerForEvent("onOverlayClose", function()
    shouldDraw = false
end)

registerForEvent("onUpdate", function(dt)
    Radio:Update(dt)
end)

registerForEvent("onDraw", function()
    if not shouldDraw then return end

    if ImGui.Begin("RadioControl", ImGuiWindowFlags.NoScrollbar) then
        if ImGui.BeginTabBar("RadioControlTabs", ImGuiTabBarFlags.None) then

            Radio:Draw()

            ImGui.EndTabBar()
        end
    end
    ImGui.End()
end)
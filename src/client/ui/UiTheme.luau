--!strict

local TweenService = game:GetService("TweenService")

local UiTheme = {}

UiTheme.FONT = Enum.Font.RobotoMono
UiTheme.FONT_BOLD = Enum.Font.RobotoMono

UiTheme.TEXT = Color3.fromRGB(238, 238, 236)
UiTheme.TEXT_DIM = Color3.fromRGB(168, 168, 164)
UiTheme.PANEL = Color3.fromRGB(16, 17, 19)
UiTheme.PANEL_LIGHT = Color3.fromRGB(28, 30, 33)
UiTheme.ACCENT = Color3.fromRGB(198, 164, 74)
UiTheme.DANGER = Color3.fromRGB(178, 58, 48)
UiTheme.OK = Color3.fromRGB(108, 138, 96)

UiTheme.PANEL_TRANSPARENCY = 0.08
UiTheme.APPEAR_TIME = 0.16
UiTheme.SLIDE_OFFSET = 18

local APPEAR_INFO = TweenInfo.new(UiTheme.APPEAR_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

function UiTheme.styleText(label: TextLabel | TextButton, dim: boolean?)
	label.Font = UiTheme.FONT
	label.TextColor3 = if dim then UiTheme.TEXT_DIM else UiTheme.TEXT
	label.TextStrokeTransparency = 1
end

function UiTheme.stylePanel(frame: Frame)
	frame.BackgroundColor3 = UiTheme.PANEL
	frame.BackgroundTransparency = UiTheme.PANEL_TRANSPARENCY
	frame.BorderSizePixel = 0
end

function UiTheme.appear(object: GuiObject, targetPosition: UDim2)
	object.Position = targetPosition + UDim2.fromOffset(0, UiTheme.SLIDE_OFFSET)
	local originalTransparency = object.BackgroundTransparency
	object.BackgroundTransparency = 1
	TweenService:Create(object, APPEAR_INFO, {
		Position = targetPosition,
		BackgroundTransparency = originalTransparency,
	}):Play()
end

function UiTheme.fadeIn(object: GuiObject, delay: number?)
	task.delay(delay or 0, function()
		if object.Parent then
			UiTheme.appear(object, object.Position)
		end
	end)
end

return UiTheme

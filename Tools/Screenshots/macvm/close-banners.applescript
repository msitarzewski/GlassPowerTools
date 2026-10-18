-- Closes the notification banners on screen (macOS 26), so none stands over a screenshot.
tell application "System Events"
	tell process "NotificationCenter"
		set closed to 0
		try
			repeat with banner in (groups of scroll area 1 of group 1 of group 1 of window "Notification Center")
				repeat with anAction in (actions of banner)
					if description of anAction is "Close" or name of anAction contains "Close" then
						perform anAction
						set closed to closed + 1
						exit repeat
					end if
				end repeat
			end repeat
		end try
		return closed
	end tell
end tell

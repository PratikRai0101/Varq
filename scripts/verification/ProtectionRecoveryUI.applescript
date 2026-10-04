-- Only the recorded PID of the separately signed production UI copy is driven.
-- SwiftUI can expose button labels as attributed AX descriptions
-- unreadable by System Events. Assert the recovery heading and absence/presence
-- of the real library toolbar instead; click the sole recovery-content button.
on isBlocked(theWindow)
    tell application "System Events"
        try
            if exists toolbar 1 of theWindow then return false
            return exists static text "Library recovery" of group 1 of theWindow
        on error
            return false
        end try
    end tell
end isBlocked

on isLibrary(theWindow)
    tell application "System Events"
        try
            return exists toolbar 1 of theWindow
        on error
            return false
        end try
    end tell
end isLibrary

on retryRecovery(theWindow)
    if not my isBlocked(theWindow) then error "Expected the real recovery screen before Retry"
    tell application "System Events"
        if (count of buttons of group 1 of theWindow) is not 1 then error "Expected exactly one recovery-content button"
        click button 1 of group 1 of theWindow
    end tell
end retryRecovery

on run argv
    set targetPID to (item 1 of argv) as integer
    set mode to item 2 of argv
    repeat 150 times
        tell application "System Events" to set registered to exists (first application process whose unix id is targetPID)
        if registered then exit repeat
        delay 0.2
    end repeat
    if not registered then error "Verification UI process did not register"
    tell application "System Events"
        set targetProcess to first application process whose unix id is targetPID
        set frontmost of targetProcess to true
    end tell
    if mode is "blocked" then
        repeat 150 times
            tell application "System Events" to set theWindows to windows of targetProcess
            if (count of theWindows) is 1 then
                if my isBlocked(item 1 of theWindows) then exit repeat
            end if
            delay 0.2
        end repeat
        if (count of theWindows) is not 1 then error "Expected exactly one initial verification window; got " & (count of theWindows)
        if not my isBlocked(item 1 of theWindows) then error "Recovery screen did not appear"
        tell application "System Events"
            tell targetProcess to click menu item "New Window" of menu "File" of menu bar 1
        end tell
        repeat 150 times
            tell application "System Events" to set theWindows to windows of targetProcess
            if (count of theWindows) is 2 then
                if my isBlocked(item 2 of theWindows) then exit repeat
            end if
            delay 0.2
        end repeat
        if (count of theWindows) is not 2 then error "Second window did not appear"
        repeat with theWindow in theWindows
            if not my isBlocked(theWindow) then error "A window exposes the library instead of recovery"
        end repeat
        my retryRecovery(item 1 of theWindows)
        delay 0.5
        repeat with theWindow in theWindows
            if not my isBlocked(theWindow) then error "Retry bypassed blocking with unknown content"
        end repeat
        return "PASS: both real windows block library access and failed Retry stays blocked"
    else if mode is "retry" then
        tell application "System Events" to set theWindows to windows of targetProcess
        if (count of theWindows) is not 2 then error "Expected both blocked windows to remain open"
        my retryRecovery(item 1 of theWindows)
        repeat 150 times
            tell application "System Events" to set theWindows to windows of targetProcess
            if (count of theWindows) is not 2 then error "A window disappeared during recovery"
            if my isLibrary(item 1 of theWindows) and my isLibrary(item 2 of theWindows) then exit repeat
            delay 0.2
        end repeat
        repeat with theWindow in theWindows
            if my isBlocked(theWindow) then error "Successful Retry failed to release all windows"
            tell application "System Events"
                if not (exists toolbar 1 of theWindow) then error "Library toolbar did not replace recovery screen"
            end tell
        end repeat
        return "PASS: successful Retry in one real window releases both libraries"
    end if
    error "Unknown UI verification mode"
end run

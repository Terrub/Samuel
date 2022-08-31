# Samuel

## Description
A swing timer that indicates the next expected swing and/or shot to happen by displaying a white bar that fills up a darker background.

Two bars are currently present.
 - The top bar represents the melee swing timer
 - The bottom bar represents the ranged swing timer

### INSTALLATION

#### From here on github:
 - On the right of the github page, under the header 'Releases', click the "tags" button
 - Click the tag called: "latest"
 - Under the header 'Assets' click and download the file: `Samuel.zip`
 - Opening the Samuel.zip archive should show a single folder called `Samuel`
 - Copy that folder inside the /Interface/AddOns/ folder of your client.

### SLASH COMMANDS
 - `/sam [command] [parameters]`
 - `/samuel [command] [parameters]`

#### Available Commands
 - `setMarkerSize [0.0+]` -- Set the amount of seconds of your swing time the marker should cover
 - `setRangedMarkerSize [0.0+]` -- Set the amount of seconds of your ranged time the marker should cover
 - `showMarker` -- Toggle whether the red marker is showing
 - `showRangedMarker` -- Toggle whether the red marker is showing for ranged
 - `lock` -- Toggle whether the bar is locked to the screen
 - `activate` -- Toggle whether the AddOn itself is active
 - `setBarWidth [0+]` -- Set the width of the bar
 - `setBarHeight [0+]` -- Set the height of the bar

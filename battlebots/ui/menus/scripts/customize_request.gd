class_name CustomizeRequest
extends RefCounted
## One-shot Garage -> Customize hand-off: the part slot Customize opens at next.
## Kept apart from the screen script: a static var there keeps its preloaded
## scenes and models alive, which leaked renderer resources at exit.
static var slot := ""

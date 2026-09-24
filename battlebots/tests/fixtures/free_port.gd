extends RefCounted
## A UDP port the OS reports free for a test server. Ports derived from the
## process id could land on a busy or reserved port (Windows excludes whole
## ranges), so an ENet host occasionally failed to bind on CI. Binding port 0
## lets the OS choose from its usable ephemeral range; the probe is released
## immediately so the fixture's own host can bind it.

static func udp() -> int:
	var probe := PacketPeerUDP.new()
	var error := probe.bind(0, "*")
	assert(error == OK, "OS assigns a free UDP port")
	var port := probe.get_local_port()
	probe.close()
	return port

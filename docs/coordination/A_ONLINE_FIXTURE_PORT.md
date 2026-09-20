# A online HTTP fixture port repair — 2026-09-20

## Intent and boundary

A repairs its loopback HTTP test fixture and online-menu test startup. No production
service, networking contract, B combat/control path or external deployment changes.
The helper is shared only by A's online-menu and public-service-client fixtures.

## Evidence

[Windows run 35503755098](https://github.com/fumbleforce/battlebots/actions/runs/35503755098)
at `9a3053a` failed presentation with `Online UI HTTP fixture binds`, followed by
requests to `http://127.0.0.1:0/healthz`, cascading assertions and `ONLINE MENU FAIL`
(exit 1). Combat HUD session and reconnect checks had passed. This was not the
separate native shutdown failure seen in run 35504840930.

The previous helper tried 20 adjacent PID-derived ports in 47000–55019 and then
discarded the actual bind error. The exact CI socket failure cannot be recovered;
a collision or reserved range is plausible, not proven.

## Change

Bind once to loopback port zero and retain the listening socket. Publish the actual
assigned port from `get_local_port()`. Report the attempted endpoint plus Godot's
actual error on failure. The menu test now cleans up and exits immediately after
a failed bind instead of proceeding with port zero. Its real HTTP and ENet checks
are otherwise unchanged. An optional explicit port is used only by fixture tests
to exercise occupied-port failure and cleanup/reuse.

API verification: the official [TCPServer documentation](https://docs.godotengine.org/en/stable/classes/class_tcpserver.html)
documents local-port retrieval. The pinned [4.7.2 TCPServer source](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/tcp_server.cpp)
passes the requested port through to socket binding and reads the actual socket
address; [SocketServer source](https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/socket_server.cpp)
closes failed binds and returns the bind error category. Local runtime validation
confirms port-zero assignment works in the pinned Windows executable.

## Validation

Godot 4.7.2 stable, headless, real time, strict exit-code checks:

- `tests/services/fake_public_api_port_test.gd`: `HTTP FIXTURE PORT PASS`, exit 0.
  Holds an occupied listener, verifies explicit bind failure (Already in use, 22),
  allocates an independent endpoint, performs a real HTTP health request and checks
  that removing a fixture releases its port for reuse.
- `tests/presentation/online_menu_test.gd`: `ONLINE MENU PASS`, exit 0.
- `tests/services/public_service_client_test.gd`: `PUBLIC SERVICE CLIENT PASS`, exit 0.

No test failures, script errors or native exits in these runs. The occupied-port
diagnostic in the targeted test is intentional. Remote CI validation remains for
the integrating parent; no workflow was restarted or cancelled. The combined
local presentation suite subsequently passed, including the newly registered
port check, online menu and public-service client checks.

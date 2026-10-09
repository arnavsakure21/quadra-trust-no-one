# QUADRA

QUADRA is a procedural, four-player co-op escape game built with Godot 4 and GDScript. It uses Godot's high-level multiplayer API over ENet; no third-party plugins or art assets are required.

## Run

Open this folder in Godot 4.x and run `scenes/main.tscn` (or press F6 with `main.tscn` selected). The project starts in the host/join menu.

## Play

- Host a game and share the displayed UDP port, or join with the host's direct IP address.
- Exactly four operators are required before the host can start. Roles are assigned in peer order, one each: Blue Hacker, Green Engineer, Yellow Scout, Red Guardian.
- Move with **WASD** or the **arrow keys**. Press **E** to collect a revealed fragment, revive a downed teammate, or use the evacuation console. Press **F** for your role ability.
- Engineer: reach the reactor in the northwest and use F to repair it.
- Hacker: use F at the security panel by the central door. After breaching, F at that panel temporarily suppresses the hazard field.
- Scout: use F to pulse nearby hidden clues and traps, then press E at each revealed clue. The fragments reveal the three-digit code.
- Guardian: press F to shield nearby teammates from hazard damage.
- Recover all three fragments, restore reactor power, breach security, enter the recovered code at the evacuation console, and have every connected operator reach the exit before the 10-minute timer expires.
- Hazards deal damage over time. Teammates can revive an incapacitated player with E; otherwise they recover after a short delay. A crew wipe or timeout loses the match.

The host can restart by returning to the lobby and starting another match. If a player disconnects during a match, their character becomes an inactive marker, the remaining crew can use that missing role's ability as needed, and only connected operators need to evacuate.

## Multiplayer limitations

This MVP uses direct ENet connections. It has no matchmaking, account system, relay, NAT traversal, or automatic LAN discovery. Players on the same LAN can usually connect using the host's private IPv4 address. For connections over the public internet, the host may need to allow or forward the selected **UDP** port (default `27145`) through their firewall/router, and the joining players need the host's reachable public IP. Network setup varies by router and ISP; carrier-grade NAT may prevent direct hosting. The host simulates movement, validates interactions and puzzle state, and owns the match timer. If the host disconnects, the match ends for everyone. Godot documents that ENet uses UDP in its [ENetMultiplayerPeer reference](https://docs.godotengine.org/en/4.4/classes/class_enetmultiplayerpeer.html).

There is no bundled Godot executable. Use a local Godot 4.x installation to run or export the project.

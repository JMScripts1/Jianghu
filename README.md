# Jianghu

A parry based, momentum driven Murim action RPG for Roblox. Combat is about timing and reading your opponent, and movement is about chaining parkour moves into speed you can fight with.

**Status:** pre-alpha. Movement is fully designed and under construction. Combat is next.

## Principles

- **R6 only.** Every player and NPC uses the R6 rig, with R6 animations.
- **Server authority.** The server owns combat state, cooldowns, hits and damage. The client sends intents ("dash", "attack"), never results.
- **Responsive movement.** The client moves its own character so it feels instant. The server checks movement and keeps its own record of what each player is allowed to be doing.
- **Tunable.** Every timing, range and cooldown is a config constant, tuned by playing at real ping.
- **Strict Luau.** `--!strict` everywhere, one entry point per side, and no state in shared code.

## Movement

Movement is a state machine with three groups. Each group holds the states a character can be in.

| Group    | States                                                      |
| -------- | ----------------------------------------------------------- |
| Grounded | Idle, Walk, Run, Slide, Crouch Idle, Crouch Walk            |
| Airborne | Jump, Double Jump, Slide Jump, Ledge Leap, Fall, the dashes |
| Wall     | Wall Run, Wall Leap, Wall Cling, Wall Boost, Mantle         |

Dash is four states, one per direction, and it doubles as the dodge: the dash grants the invincibility frames. Nothing cuts a dash short, and it hands over to whatever the character is doing once it ends. Front and back share one cooldown and the sides share another, so a side dash chains into a front one on the ground. In the air there is one dash until landing, and a wall run or wall boost gives it back. A ground dash that carries off a ledge uses it. A front dash in the air is an air dash: a faster burst that rises a little and adds to momentum.

### Controls

| Action  | Input                                                                                     |
| ------- | ----------------------------------------------------------------------------------------- |
| Sprint  | Double tap W, held while W stays down                                                     |
| Slide   | Ctrl while sprinting                                                                      |
| Crouch  | Ctrl while standing or walking, toggles. Jump while crouched stands up                    |
| Jump    | Space. Becomes a double jump, wall run, wall cling, leap, boost or mantle depending on state |
| Mantle  | Space or F near a ledge, in the air or on a wall                                          |
| Dash    | Q, direction from the movement key held. No key held dashes back                         |

### Momentum

Momentum is carried horizontal speed. Parkour moves add to it and walking drops it back to walking speed, so stringing moves together is what builds speed.

- Sliding boosts speed, and sliding downhill keeps adding to it.
- A slide jump launches along the slide. One that clears a drop just after takeoff becomes a ledge leap, a stronger launch that adds momentum.
- Wall leaps and air dashes each add a burst, and a wall cling adds a little.
- Repeating the same move gives less each time.
- Just running holds momentum for a couple of seconds, then it tapers back to run speed.
- A mantle and every other dash leave momentum unchanged.
- Momentum is capped.
- A big enough drop lands in a roll that carries the character forward.

### Wall movement

A jump in the air next to a wall starts a wall run when you are moving along it, or a wall cling when you are facing it. A wall run ends in a leap away from the wall. A cling ends in a boost straight up it. A ledge in reach always wins: Space pulls up onto it instead. A wall takes one cling and one run before landing, so longer chains have to move between walls.

### Effects

The camera widens with speed. Every move has a sound slot, empty until a sound is added. Roblox's default character sounds are turned off. Footsteps are custom: they keep time with the walk and run animations, and sound like whatever the floor is made of.

### Server checks

The client decides what to do and the server verifies it:

- Every movement intent is rate limited, type checked and validated against a transition table.
- Wall, ground and ledge checks are repeated on the server from its own positions, with slack for the server's slightly old view.
- Speed is sampled on an interval against what the recorded states allow. Sustained excess is rubber banded back to the last good position.
- Mantles only work on parts tagged `Mantleable`, and walls only count when anchored.

## Roadmap

| Phase | Focus                  | Status      |
| ----- | ---------------------- | ----------- |
| 1     | Movement               | In progress |
| 2     | Combat                 | Next        |
| 3     | Detection and tuning   | Planned     |
| 4     | World, NPCs, progression | Planned   |

**Phase 2: Combat.** Parry based melee built on the same server state as movement.

- Light and heavy attacks with windup, active and recovery frames
- Block, with posture loss on blocked hits
- Parry as a timed window with a cost for missing, resolved in order: dodge, parry, block, hit
- Server side hitboxes, one hit per target per swing
- Stun and downed states

Data, inventory, trading and UI come after the core combat loop is working.

## Tooling

Rojo, Rokit, luau-lsp, StyLua and Selene. Studio needs the avatar type set to R6 and StreamingEnabled on.

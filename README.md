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

| Group    | States                                                  |
| -------- | ------------------------------------------------------- |
| Grounded | Idle, Walk, Run, Slide, Crouch Idle, Crouch Walk, Low Vault |
| Airborne | Jump, Double Jump, Slide Jump, Fall                     |
| Wall     | Wall Run, Wall Leap, Wall Cling, Wall Boost, Mid Vault  |

Dash is not a state. It is an action available from most grounded and airborne states, in four directions, and it doubles as the dodge: the dash grants the invincibility frames.

### Controls

| Action     | Input                                                    |
| ---------- | -------------------------------------------------------- |
| Sprint     | Double tap W, held while W stays down                    |
| Slide      | Ctrl while sprinting                                     |
| Crouch     | Ctrl while standing or walking, toggles                  |
| Jump       | Space. Becomes a double jump, wall run, wall cling, leap or boost depending on state |
| Mid vault  | Space in a wall cling or wall boost, near a ledge        |
| Dash       | Q                                                        |
| Low vault  | Automatic when running into a low obstacle               |

### Momentum

Momentum is carried horizontal speed. Parkour moves add to it and standing or walking lets it decay, so stringing moves together is what builds speed.

- Sliding boosts speed, and sliding downhill keeps adding to it.
- Slide jumps, wall leaps and low vaults each add a burst.
- Repeating the same move gives less each time.
- A mid vault cancels momentum.
- Momentum is capped, and exposed to animations and effects as three tiers.

### Wall movement

A jump in the air next to a wall starts a wall run when you are moving along it, or a wall cling when you are facing it. A wall run ends in a leap away from the wall. A cling ends in a boost straight up it, or a mid vault if there is a ledge in reach. A wall cannot be grabbed twice in a row, so chains have to move between walls.

### Server checks

The client decides what to do and the server verifies it:

- Every movement intent is rate limited, type checked and validated against a transition table.
- Wall, ground and vault checks are repeated on the server from its own positions.
- Speed is sampled on an interval against what the recorded states allow. Sustained excess is rubber banded back to the last good position.
- Vaults only work on parts tagged `Vaultable`, and walls only count when anchored.

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

# LC Gamemode

A GTA IV roleplay gamemode framework built for HappinessMP.

**Author:** Baldne55

---

## Usage Restriction

This framework is free to use, modify, and build upon by anyone — **except** the following:

- **Heavenly**
- **Skitzo**
- **The Liberty City - Roleplay (LC-RP) community**
- **Any person or group associated with the above**

These individuals and their community are explicitly prohibited from using, copying, adapting, or redistributing any part of this codebase. Everyone else is welcome.

---

## Getting Started

### Requirements

- [HappinessMP](https://happiness-mp.com) server with GTA IV Episode 2 (TBOGT)
- MySQL X (production) or SQLite (development)

### Configuration

**Database** — set via environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `LCRP_DB_TYPE` | `0` = MySQL X, `1` = SQLite | `0` |
| `LCRP_DB_URL` | Connection string | `mysqlx://root@localhost:33060/lc-rp` |

**Server** — edit `settings.xml`:

| Setting | Description | Default |
|---------|-------------|---------|
| `host` | Bind address | `0.0.0.0` |
| `port` | Server port | `9999` |
| `max_players` | Player limit | `100` |
| `episode` | GTA IV episode (2 = TBOGT) | `2` |

### Starting the Server

1. Place the gamemode in your HappinessMP server's `resources/` directory.
2. Set your database environment variables.
3. Run `HappinessMP.Server.exe`.
4. The server auto-creates all database tables and runs migrations on first start.

---

## Features

### Authentication

Players log in or register through an in-game UI on connect.

- **Login / Register** — username + password with a tabbed interface
- **Brute-force protection** — 5 failed attempts triggers a 15-minute IP lockout
- **Password security** — SHA-256 hashing with random 32-character hex salt
- **Account status** — Unverified, Active, or Locked (with timed lock support)
- **RGSC linking** — accounts are tied to Rockstar Social Club IDs
- **Staff levels** — 14 tiers from None to Lead Web Developer
- **Premium levels** — None, Bronze, Silver, Gold, Platinum (with expiration dates)
- **Session tracking** — first login, last login, last logout, last IP

### Characters

Each account can hold multiple characters (default 3 slots, expandable via premium/staff).

- **Creation wizard** — first name, last name, date of birth, gender, blood type, skin model, appearance customization
- **Unique identifiers** — every character gets a random SSN (XXX-XX-XXXX), DNA ID, fingerprint ID, and mask ID
- **Age system** — age calculated from in-universe birth date (server year: 2008), range 14–90
- **Appearance** — per-component clothing customization (11 slots: head, torso, legs, hands, shoes, jacket, hair, etc.)
- **Persistence** — position, health, armour, cash, appearance, and all preferences saved on disconnect
- **Per-character settings** — chat font size, chat page size, money HUD toggle, notification style, inventory UI style

### Chat System

Proximity-based roleplay chat with multiple channels.

| Chat Type | Range | Color |
|-----------|-------|-------|
| Normal (IC) | 10 units | White |
| Low | 5 units | White |
| Whisper | 3 units | Orange |
| Shout | 20 units | White |
| OOC | 10 units | Grey |
| ME / DO | 10 units | Purple |
| Admin | Global | Red |
| PM | Direct | Yellow |

- **Command autocomplete** — type `/` and get a dropdown with all available commands, descriptions, and aliases
- **Input history** — arrow up/down to cycle through previous messages (up to 100)
- **Font size** — adjustable 12–24px via `/fontsize` or settings panel
- **Page size** — adjustable 10–30 lines via `/pagesize` or settings panel
- **Character counter** — shows current/max (255) while typing
- **F7 toggle** — hides/shows all HUD elements (chat, money, notifications)
- **Cooldown** — 500ms between messages to prevent spam

### Inventory System

Full inventory management with 196 item definitions across 10 categories.

**Core Features:**
- **Slot-based** — 20 slots per character (configurable)
- **Weight system** — 50kg max carry weight (configurable)
- **Stacking** — items stack up to their defined max (1 for weapons, 50+ for consumables)
- **Containers** — items like duffel bags, backpacks, and briefcases hold other items with their own slot/weight limits
- **Quality & purity** — tracked per item (0–100 scale) for food, drugs, tools
- **Serial numbers** — auto-generated for weapons and phones (e.g., `WPN-A3K8M2`)
- **Custom metadata** — extensible JSON data per item instance
- **Dropped items** — 3D world labels visible within 3m, auto-expire after 1 hour
- **Audit trail** — every item movement (give, drop, pickup, store, admin create/delete) logged to database
- **Dual UI** — graphical WebUI (toggle with `I` key) or text-based chat display

**Item Categories:**

| Category | ID Range | Examples |
|----------|----------|---------|
| Weapons | 1–19 | Baseball Bat, Knife, Pistol, Assault Rifle, RPG |
| Ammo | 20–27 | 9mm, .45 ACP, 5.56mm, 7.62mm, Shotgun Shells |
| Narcotics | 28–61 | Cocaine, Heroin, Cannabis, LSD, Xanax |
| Food | 62–81 | Burger, Pizza, Sandwich, Banana, Donut |
| Drinks | 82–97 | Water, Beer, Whiskey, Coffee, Champagne |
| Materials | 98–122 | Lockpick, Radio, Jerry Can, Cannabis Seeds, Lab Beakers |
| Containers | 123–154 | Duffel Bag, Backpack, Briefcase, Ziplock Bags, Gun Case |
| Clothing | 155–157 | Mask, Gloves, Body Armor |
| Tools | 158–182 | First Aid Kit, Flashlight, Defibrillator, Evidence Bag |
| Miscellaneous | 183–196 | Phone, GPS, Driver License, Dice, Notepad |

**Inventory Commands:**

| Command | Aliases | Description |
|---------|---------|-------------|
| `/inventory` | `/inv` | View your inventory |
| `/giveitem <player> <slot> <amount>` | `/gi` | Give item to nearby player (5m range) |
| `/dropitem <slot> <amount>` | `/di` | Drop item on the ground |
| `/pickup <dropID> [amount]` | | Pick up a nearby item (3m range) |
| `/useitem <slot>` | | Use or consume an item |
| `/equip <slot>` | | Equip a weapon from inventory |
| `/unequip` | | Stow your equipped weapon |
| `/moveitem <from> <to> [amount]` | | Rearrange inventory slots |
| `/nameitem <slot> <name>` | | Give an item a custom name |
| `/nearbyitems` | | List dropped items near you |
| `/container <slot>` | `/c` | View contents of a container |
| `/store <containerSlot> <itemSlot> <amount>` | | Store item in a container |
| `/retrieve <containerSlot> <itemSlot> [amount]` | | Take item from a container |

### Banking

Polymorphic bank accounts supporting characters, factions, and companies.

- **Account types** — checking (everyday) and savings (may require character level)
- **Routing numbers** — unique 9-digit identifiers per account
- **Transaction log** — every deposit, withdrawal, transfer, salary, and adjustment recorded
- **Default accounts** — characters spawn with a checking account ($15,000) and savings account ($135,000, requires level 5)
- **Money HUD** — real-time display of cash and total bank balance (top-right corner, toggle with `/togglemoneyhud`)

### Cash System

| Command | Description |
|---------|-------------|
| `/pay <player> <amount>` | Transfer cash to a nearby player (5m range, max $100,000) |
| `/togglemoneyhud` | Show/hide the money HUD |

All cash operations are atomic — no duplication or overdraft possible.

### Factions

Hierarchical organizations for roleplay groups (police, EMS, gangs, government, news, etc.).

**Structure:**
- Up to 3 levels deep (faction → sub-faction → department)
- 8 faction types: `illegal`, `government`, `police`, `ems`, `fire`, `news`, `legal`, `other`
- Characters can belong to multiple factions simultaneously
- Each faction gets its own bank account

**Rank System:**
- Rank 1 = leader (all permissions automatically)
- Higher rank numbers = lower authority
- 8 permission flags: Invite, Kick, Promote, Demote, Manage Ranks, Manage Bank, Set MOTD, Duty

**Faction Commands:**

| Command | Description |
|---------|-------------|
| `/f` | Faction chat |
| `/finvite <player>` | Invite a player |
| `/fkick <player>` | Remove a member |
| `/fpromote <player>` | Promote a member |
| `/fdemote <player>` | Demote a member |
| `/franks` | List all ranks |
| `/fmembers` | List all members |
| `/finfo` | View faction info |
| `/fsetmotd <message>` | Set message of the day |
| `/fleave` | Leave the faction |
| `/fduty` | Toggle on-duty status (police/ems/fire only) |
| `/fcreaterank <name>` | Create a new rank |
| `/fdeleterank <rankID>` | Delete a rank |
| `/feditrank <rankID>` | Edit rank permissions |

### Companies

Parallel system to factions for businesses.

- 5 company types: `llc`, `sole_proprietorship`, `partnership`, `corporation`, `nonprofit`
- Same hierarchy, rank, and permission system as factions
- All commands mirror factions with `/c` prefix: `/cinvite`, `/ckick`, `/cpromote`, `/cdemote`, `/cranks`, `/cmembers`, `/cinfo`, `/csetmotd`, `/cleave`, `/ccreaterank`, `/cdeleterank`, `/ceditrank`

### Death & Injury

- **Death timer** — 120-second delay before accepting death
- **Hospital respawn** — configurable spawn location with reduced health (51 HP)
- **Help up** — nearby players can `/helpup` a downed player within 3m (restores to 51 HP)
- **Server-authoritative** — all health and armour changes validated server-side

### Weapons

19 weapon types integrated with the inventory system:

| Type | Weapons |
|------|---------|
| Melee | Baseball Bat, Pool Cue, Knife |
| Throwables | Grenade, Molotov Cocktail |
| Pistols | Pistol, Silenced Pistol, Combat Pistol |
| Shotguns | Combat Shotgun, Pump Shotgun |
| SMGs | Micro-SMG, SMG |
| Rifles | Assault Rifle, Carbine Rifle |
| Snipers | Combat Sniper, Sniper Rifle |
| Heavy | RPG, Flamethrower, Minigun |

- Weapons must be equipped from inventory via `/equip`
- Ammo is tracked and synced between client and server
- Unequipping returns remaining ammo to inventory
- Ammo is returned on disconnect

### Settings Panel

Open with `/settings` (aliases: `/prefs`, `/preferences`). Three tabs:

- **Account** — change your password in-game
- **Chat** — adjust font size (12–24) and page size (10–30) with sliders
- **Interface** — toggle Money HUD, UI Notifications, and Inventory UI mode

All preferences are saved per character and persist across sessions.

### Anti-Cheat

Server-authoritative validation running on background timers:

- **Weapon audit** (every 3s) — scans for unauthorized weapons and removes them; heartbeat detection (every 15s) catches scanner suppression
- **Health/armour validation** (every 15s) — cross-checks client-reported values against server-authoritative state; increases only allowed during server-opened heal windows
- **Ammo sync** (every 500ms) — validates ammunition counts against server records
- **Position bounds** — rejects coordinates outside GTA IV map limits

### Admin Commands

All require staff level.

**Item Management:**

| Command | Aliases | Description |
|---------|---------|-------------|
| `/agiveitem <item> [amount] [player]` | `/agi` | Give any item to a player |
| `/deleteitem <slot>` | `/adi` | Delete an item from inventory |
| `/inspectitem <slot>` | | View full item metadata |

**Faction Administration:**

| Command | Description |
|---------|-------------|
| `/acreatefaction <name> <type>` | Create a new faction |
| `/adeletefaction <factionID>` | Delete a faction |
| `/acreatesubfaction <parentID> <name>` | Create a sub-faction |
| `/asetfactionleader <player> <factionID>` | Set faction leader |
| `/aremovefactionleader <player> <factionID>` | Remove faction leader |
| `/afactionaddmember <player> <factionID>` | Force-add a member |
| `/afactionremovemember <player> <factionID>` | Force-remove a member |
| `/afactioninfo <factionID>` | View faction details |
| `/afactions` | List all factions |

**Company Administration:**

Same as faction admin commands with "company" replacing "faction" — `/acreatecompany`, `/adeletecompany`, etc.

**Other:**

| Command | Description |
|---------|-------------|
| `/noclip` | Toggle noclip flight (WASD + Shift/Ctrl) |

### Utility Commands

| Command | Aliases | Description |
|---------|---------|-------------|
| `/clearchat` | `/cls` | Clear chat window |
| `/coords` | `/pos`, `/mypos` | Show your position and heading |
| `/camcoords` | `/campos` | Show camera position |
| `/fontsize [size]` | | Set or view chat font size |
| `/pagesize [size]` | | Set or view chat page size |
| `/toggleuinotifications` | | Switch between toast and chat notifications |

---

## Architecture

```
resources/lc-rp/
  core/           Command system (client + server dispatchers)
  shared/         JSON utilities
  chat/           Chat UI, health/ammo/position sync, weapon audit
  client/
    config.lua    Client settings (camera, spawn, sync intervals)
    cmds.lua      Client-side commands
    handlers/     Auth, character, notifications, HUD, inventory UI, settings, noclip
    ui/           WebUI panels (login, character, inventory, settings, notifications, money HUD)
    utils/        Player state, appearance, WebUI helpers
  server/
    config.lua    Server settings (DB, auth, chat, world, death, inventory)
    server.lua    Entry point (DB lifecycle, migrations, background tasks)
    players.lua   In-memory session cache
    api/          CharState, Inventory, Org APIs
    handlers/     Auth, character, inventory, pay, factions, companies, settings, noclip
    utils/        Guard, logging, notifications, hashing, resolve, item registry, org helpers
    db/
      database.lua   MySQL X / SQLite abstraction
      model.lua      ORM factory (define, sync, create, find, update, delete, upsert)
      migrations.lua Migration runner
      models/        Account, Character, BankAccount, BankTransaction, ItemDefinition,
                     InventoryItem, DroppedItem, ItemTransfer, Faction, FactionRank,
                     FactionMember, Company, CompanyRank, CompanyMember
```

**Key design decisions:**
- **Server-authoritative** — all mutations (health, cash, items, positions) validated server-side
- **Async callbacks** — all DB operations are non-blocking with `cb(result, err)` pattern
- **In-memory caching** — player sessions and inventories cached in Lua tables for performance
- **Atomic operations** — cash transfers and item moves use SQL guards to prevent duplication
- **Per-item locks** — prevent race conditions during concurrent inventory operations
- **Auto-migrations** — schema changes applied automatically on server start
- **Dual database support** — MySQL X for production, SQLite for development

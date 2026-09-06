# The Viceroy Community Fix 1.0.0

Unofficial community bug-fix patch for the Windows/Steam release of **The Viceroy**.

This package contains **no original game files**. It modifies the copy of
`the viceroy__main__.pyc` already present inside the player's own `library.zip`.

## What it fixes

### 1. Crash when no valid audio device exists

When Windows loses its usable audio device/mixer (observed after Bluetooth audio
disconnects), the game can crash while processing a turn with:

    UnboundLocalError: local variable 'tutorialChannel' referenced before assignment

The game creates `tutorialChannel` only when `pygame.mixer.get_init()` succeeds,
but later calls `tutorialChannel.stop()` without first checking that the channel
exists.

The patch removes that unsafe stop call at the confirmed crash site. Turn
processing continues normally when the mixer is unavailable.

### 2. Millennial Reign achievement

**Millennial Reign** is described as:

    Reign over a single Territory for one thousand turns.

The shipped game increments one entry in the current Territory's
`weightOfCulture` dictionary each turn, then checks approximately:

    gameData['territory']['weightOfCulture'].values() == 1000

That compares the dictionary's collection of values itself with the integer
`1000`, so the condition can never be true.

The patch restores the intended test:

    sum(gameData['territory']['weightOfCulture'].values()) == 1000

The game's original Steam achievement call is otherwise left in place.

## Installation

1. Close The Viceroy.
2. Extract this ZIP somewhere outside the Steam game directory.
3. Double-click `ViceroyFix.exe`.
4. The patcher will look for the usual Steam install location.
5. If your Steam library is elsewhere, paste the full path to either:
   - the `The Viceroy` game folder, or
   - its `library.zip`.
6. Choose **Apply both bug fixes**.
7. Start The Viceroy normally through Steam.

Before modifying an original supported installation, the patcher creates:

    library.zip.viceroyfix-original

The patcher verifies that the backup contains the supported original main game
file before relying on it. It will not silently replace a verified original
backup on later runs.

If the game is already modified and no verified original backup exists, the
patcher refuses to create a misleading "original" backup. Use Steam's **Verify
integrity of game files** to restore the supported original build, then run the
patcher again.

## Supported build

The currently supported original `the viceroy__main__.pyc` SHA-256 is:

    9b69230360a2b7a8fd3b4cb8cee06e81ddebcc4cd7ea05f4008c0d9fb39433f2

Audio-fix-only state:

    35dd99256a689d39a14e6a8d99ca145daa25dbea9591b12e7007a58fc90e3c5d

Both fixes installed:

    37a862f889ffcde626beaf2a28af72e4fa623cc430b5f90ff794794806d59e3e

If the contained main game file does not match a recognized state, the patcher
refuses to modify it.

## Steam updates and Verify Integrity

Steam may replace modified files when the game is updated or when **Verify
integrity of game files** is run.

Keep this patch ZIP somewhere outside the Steam game directory so it can be
reapplied if necessary.

## Restore the original game

Run `ViceroyFix.exe` and choose **Restore original library.zip backup**.

The patcher verifies the saved backup before restoring it. If no verified
original backup is available, use Steam's **Verify integrity of game files**
instead.

## Technical notes

Both confirmed defects are in `the viceroy__main__.pyc`, not `steam.pyc`.

The patcher:

- verifies the exact SHA-256 of the contained main game file;
- creates and verifies an original `library.zip` backup before modifying a clean install;
- changes only the known audio crash instruction and Millennial Reign condition;
- verifies the resulting patched SHA-256 before reporting success.

`ViceroyFix.exe` is only a small native Windows launcher. It contains no game-patch
logic; it starts the adjacent `ViceroyFix.ps1` and waits for it to finish. The
launcher source is included in the repository as `ViceroyFixLauncher.c`.

A pre-release development build of this patch briefly used a temporary
Millennial Reign recovery shortcut. **That build should not be distributed.**
This public package does not contain or enable that shortcut. If it encounters
that known development state, it converts it to the repaired logic.

## Distribution

Please distribute this patch package rather than a modified copy of the game's
`.pyc` file. The patch package contains patch logic and documentation only; the
player must supply their own installed copy of The Viceroy.

## Disclaimer

Unofficial fan/community fix. Not affiliated with the developer, publisher,
Valve, or Steam. Back up your saves before modifying a game installation.

# Lessons

Traps already hit, how each was found, and what now prevents it. Read this before debugging something that
smells familiar. Add to it when you learn something; a lesson recorded is a bug not repeated.

## Qt and QML

- **`onPrimary` is a signal handler.** A QML property named `on` plus a capital is read as a handler, so
  `Colors.onPrimary` returned nothing for 17 roles. Found by a test that read every role. Now `xOn`, and the
  generator refuses `on*` names.
- **Assigning a property from JavaScript destroys its binding.** `Spring.snap(v)` assigns `target`, which froze
  every button's press morph. Found when a hover/press test never moved the radius. Added `rest()`; `snap()` is for
  unbound targets only (`tests/qml/tst_spring.qml` pins both).
- **Objects created with bound values start a transition.** `SpringColor` faded in from transparent at creation.
  Found when a pixel test read a half-faded color. It now resets on `Component.onCompleted`.
- **`for...in` does not enumerate a QML singleton's properties.** The type scale section of the gallery was empty.
  `Type.styleNames` is generated instead.
- **`property color` needs `import QtQuick`; pure data singletons only need `QtQml`.** Importing the wrong one
  fails with "color is not a type".
- **`Item` has a final property `right`.** A delegate declaring `property bool right` failed to compile.
- **Ids can shadow JavaScript globals.** `id: gc` fails with "ID illegally masks global JavaScript property".
- **Delegates should not reach into outer ids.** qmllint flags it; pass data through the model or a JS helper.
- **qmllint directive comments are keyword-parsed.** A comment beginning "qmllint ..." is treated as a directive.
  Suppress by category: `type` covers both missing `Qt.CursorShape` on Qt 6.4 and a feature-detected
  `font.variableAxes`. Keep suppressions scoped to the few lines.
- **`img.save()` returns `undefined` in Qt Quick Test**, so `verify(img.save(...))` always fails. Check the file exists.
- **`grabImage` may composite onto an opaque background** (the software renderer does), so test shape by color,
  not alpha.
- **Qt stores letter spacing in 1/64 px steps** (0.15 reads back 0.140625). Tests allow one step.
- **M3E Emphasized styles change letter spacing too** (`bodyLarge` 0.5 px, `bodyLargeEmphasized` 0.15 px), which can
  make the heavier line narrower. A width test must zero the tracking so only weight differs. This was a wrong
  test, found by reproducing a failure on the maintainer's Qt.
- **Qt 6.4 vs 6.7+:** `font.variableAxes` does not exist before about 6.7. On 6.4 weight 700 renders bold but 500
  looks like 400, and the `FILL` axis cannot be set. Feature-detect, never version-check, and skip tests loudly.
- **Distance-field text corrupts filled Material Symbols glyphs.** The software renderer ignores `renderType`, so
  every software-rendered test passed while the real GPU path showed holes. Only a real scene graph exposed it.
  Use `NativeRendering` for icons; `tests/qml_gpu/` guards it.
- **Custom properties on a repeated child cost memory.** Each instance with its own `property` declarations gets
  its own meta object: an inline `TrackPart` component with five properties added about 11 KiB per slider. Plain
  Rectangles binding to properties on their parent cost a fraction of that. An idle `Loader` is about 4 KiB, as
  much as the icon it would load, so one Loader for two icons beats two. Measure with `tools/dev/memcost.py`.
- **LayoutMirroring does not flip text that never set an alignment.** A `Text` without `horizontalAlignment`
  aligns by its own script, so Latin labels stayed left in a right-to-left tile. Set `Text.AlignLeft`
  explicitly and mirroring turns it into right; check `effectiveHorizontalAlignment` in tests. Anchors mirror,
  alignment only when set.
- **A `Row` places its children later, not when a child resizes.** Scrolling a Flickable to a chip from the
  chip's `onSelectedChanged` used the old `x` (the check mark that changes the widths had not been laid out yet)
  and scrolled 14 px past the end. Reveal again on the Row's `positioningComplete`, and clamp to the row's width.
- **`Keys` runs a key's own handler before `onPressed`.** `Keys.onUpPressed` fires first and accepts the key by
  default, so an `onPressed` that should take the arrows first (an open menu) never sees them; ask the menu in
  each key's own handler. `onPressed` does not accept by default, so typing still reaches the field.
- **A deactivated `Loader` deletes its item later.** `findChild` still finds it right after `active` goes false;
  test its absence with `tryVerify`.
- **`qmltestrunner` needs a visible `TestCase`** (`width`, `height`, `visible: true`, `when: windowShown`) for any pixel check.

- **Never size a layer-shell window to moving content.** The notification popups and list took their window's
  height from content whose height animated, so the surface was resized on every frame (34 resizes for three
  popups); each resize is a compositor round trip and a new buffer, and the motion stuttered. Size the window
  to where the motion ends (grow at once, shrink after it), or to the largest it gets, and let the `mask` pass
  clicks through the empty part. Count resizes under headless sway with `WAYLAND_DEBUG=1`
  (`zwlr_layer_surface_v1.set_size`), mapping each surface by the order of its creation: ids are reused.

- **Build a window's input mask from geometry, not `Region { item }`.** Quickshell 0.3.2 measures the item with
  its scale and does not update when the scale changes, so a mask taken while PopupMotion grew a panel from 0.85
  stayed at 0.85 of its size: Clear all at the bottom of the notification list, the left and bottom edges of
  Quick Settings and the power menu's lower part took no clicks. Bind the Region's x, y, width and height to the
  item's. Headless QML tests cannot see this (the mask exists only under a compositor); `qtws.py
  run_wayland_surfaces` checks the masks and sizes the shell sends under headless sway.

- **Never name an IpcHandler function `show`.** `quickshell ipc call osd show volume` fails with "The following
  argument was not expected: volume": the CLI reads `show` as its own `ipc show` command (Quickshell 0.3.2). An
  IPC function is not done until a test calls it through the real CLI.

- **A FileView with `watchChanges` does not see a file appear.** It watches only a file that exists (Quickshell
  0.3.2): a palette rendered after the shell started went unnoticed. PaletteWatcher looks again every 3 s while
  the file is missing. A later atomic replace (rename over the name) is seen.

- **A zero-length SequentialAnimation can run its ScriptAction twice.** With Motion.speed 0 the wallpaper's fade
  (a NumberAnimation then a ScriptAction that swapped the two images) swapped them back again, leaving nothing
  shown. A single NumberAnimation with `onFinished` runs once.
- **A Quickshell singleton is created when first used**, not at start. A test that only reads its effects (a log
  it writes) must use it first, or it reads before anything happened and passes for the wrong reason (a mutant
  survived that way).

## Testing method

- **A test that cannot fail proves nothing.** Mutate the code and watch the test fail. Several guards turned out
  vacuous this way (a quote-parity check that failed on valid Nix and passed on invalid; a "weaken the rules" attack
  test that passed against the vulnerable design). An *equivalent mutant* (changes nothing observable) is not a gap;
  mutate the real protection instead (remove the `onCompleted` reset, not the redundant guard).
- **Reproduce the user's failure before fixing it.** The maintainer's Qt 6.11 failure reproduced on Qt 6.12, and the
  real assertion text showed the test was wrong, not the code. Long output truncated the message: failing
  assertions now print first (`tools/qtws.py` `summarize`).
- **Check claims against the real tool.** Real opencode 1.19 showed the config precedence and the rule order; real
  matugen and materialyoucolor exposed the 2021 vs 2025 spec gap; the real fonts' `fvar` tables gave the axes;
  aider's source showed `--git-commit-verify` defaults to false.
- **Run on more than one Qt.** 6.4 catches old-Qt assumptions, 6.12 catches new-Qt behavior. Neither stands in for
  the maintainer's 6.11 session.
- **A sentinel must not be a value the tool can return.** `tools/qtws.py` used exit code 3 to mean "skipped", and
  qmltestrunner exits with its failure count, so a run with exactly three failures printed "SKIPPED" and exited 0.
  `make check` was safe (it asserts zero failures from the counts), but the CLI and a mutation script that read
  the exit code were not; the sentinel is now a string. Found because a mutant "survived" while its test failed.
- **Skipped is not passed.** `make check` prints a reason for every skip. Do not read a green run as "the font
  behavior was verified" if the font tests skipped.
- **Don't assert what you cannot justify.** A threshold guessed too high (95% agreement vs a measured 94.7%) was a
  guess; set bounds from measurement and say so in a comment.

- **A fake that nothing reads back can be wrong for a long time.** The fake brightnessctl in tests/qs/bin wrote all
  its arguments ("-m -c backlight -d intel_backlight set 565") into its state file instead of the value; no test
  read the state back after a set until the OSD smoke check did. When a fake keeps state, check it once.

## Nix and environment

- **Flakes only see git-tracked files.** `git add` before evaluating. A new file missing from the commit breaks the
  maintainer's shell.
- **GitHub's API is rate limited in the sandbox** (`nix flake lock` fails with HTTP 403). `tools/dev/eval_flake.sh`
  overrides nixpkgs with a codeload tarball of a known revision (`git ls-remote` works).
- **ROCm does not exist on aarch64.** `local-ai` is behind an x86_64 guard; evaluate both architectures.
- **A bare `qtdeclarative` in a nix shell leaves its QML modules off the import path** (`module "QtQuick.Window" is
  not installed`). The dev shell exports `QML2_IMPORT_PATH` from nixpkgs' own prefix, and `tools/qtws.py` derives
  it from the tool's real location as a fallback.
- **Do not export `QT_QPA_PLATFORM=offscreen` in a shell hook**: Quickshell started from it would render nowhere.
- **`sh` has no brace expansion and no `$PIPESTATUS`.** A failed `cd` chained with `&&` skipped commands silently
  and files landed in `/`. Use explicit paths and check results.
- **`package.name` is the same for every Ollama variant** (`ollama-0.40.0`). Compare derivation paths to prove
  which build a module selects.
- **GitHub raw and release assets work from the sandbox; most other hosts do not.** Prefer them for vendoring checks.

## Side-work tooling

- **Enforce rules from outside the thing being policed.** The first guard read `ownership.json` and ran
  `sidework.py` from the worktree, so editing either there weakened it. Rules and code now come from the main checkout.
- **aider skips git hooks by default** and its edit-format loop does not suit a small local model. opencode replaced it.
- **opencode 1.x silently did nothing without `"tool_call": true`**, and Ollama's 4096-token default context breaks
  an agent. Both are handled in the launcher and tested.
- **opencode 1.x and 2.x have different config schemas, and 2.x drops unknown keys silently.** A config written
  from memory of 2.x (commit c62dbf8) evaluated fine and failed every request (`Unsupported package`). The real
  schema ships with the package (config.json in its share directory), and `opencode api --standalone config.get` shows what 2.x
  kept of a config, which is the check to run. 2.x also migrates most 1.x keys (`permission` to `permissions`,
  `bash` to `shell`), which is how the right names were found.
- **Drive the real agent with a scripted model.** A ~40-line OpenAI-compatible server that answers each turn with
  the next tool call lets the real opencode be tested end to end without a GPU. It found three bugs nothing else
  had: the `PWD` one, the background-service one, and that `OPENCODE_DISABLE_PROJECT_CONFIG` also drops `AGENTS.md`.
- **`opencode run` waits for a piped stdin to end.** Tests that started it without `stdin=DEVNULL` passed or hung
  depending on how the test run itself was started (a terminal or `/dev/null`, or an open socket from Claude Code),
  which looked like flakiness and was first blamed on leftover processes. Finding it took `/proc/<pid>/fd/0` on
  the stuck process. Lesson: when a child process "sleeps", look at what it is blocked on before theorising, and
  give every child an explicit stdin. The runs now also fail after 20 s without a model request instead of
  waiting out a timeout.
- **opencode follows `$PWD`, not its real working directory.** `chdir` plus the inherited environment put the agent
  in the main checkout. The test that caught it timed out at first instead of failing, which hid the cause.
- **A local model needs a check it can run with what is installed.** The first trial (qwen3:14b, `widget-schema`)
  could not validate its schema, so it spent dozens of tool calls on `pip`, a virtualenv and rewriting `flake.nix`
  through the shell (edit permissions do not cover shell redirection), re-ran the same failing check 13 times,
  and wrote a schema that copies node definitions two levels deep instead of recursing. The brief now names
  `tools/widget_check.py` and sketches the recursive structure; the conventions forbid installing and say when
  to stop retrying.

## Process

- **Tests must not inherit the session's niri.** `NIRI_SOCKET` reached the offscreen and sway tests from the
  maintainer's session, and the shelf backend test talked to the real niri. `tools/qtws.py` now drops
  `NIRI_SOCKET` and `SWAYSOCK` from test environments; a test that needs niri starts `tests/qs/bin/fake-niri`.
  Unix socket paths must stay under 108 bytes, so the scratchpad is too deep for one; the qs workspace is not.
- **qmllint exits 0 on some warnings** (`id-shadows-member`, `incompatible-type`), so two warnings sat on main
  with `make check` green. `qtws.py lint` now fails on any `Warning:` line.

- **The maintainer's shell hot-reloads this checkout.** Mutation testing by editing files in place shows every
  mutant on their screen; mutate in a copy. A new module directory under `shell/` can make the reload fail with
  `module "qs.common" is not installed`; `touch shell/shell.qml` reloads it. `qs log -p shell/shell.qml` prints the
  running instance's log, so there is no need to start a second one.

- **Verify in a fresh clone, and read the result before delivering.** A bundle shipped with a failing check because
  `widgets/` and `settings/` existed in the working directory only as untracked empty directories (git does not
  track empty directories), so a path check passed locally and failed in every clone. The fresh-clone step was
  run, but the bundle was presented before its output was read. Tests that look at the filesystem cannot tell
  "committed" from "happens to be here": consult `git ls-files` (`tests/test_handoff.py` does now). A sandbox
  reset later made this visible, because the repo had to be rebuilt from the bundle alone.

- **Test the second interaction, not just the first.** `Spring` came to rest through `snap(target)`, which assigns
  `target` and so silently removed every `target:` binding after the first settle. Button press morphs, state-layer
  opacity and the gallery's motion lanes each worked exactly once. The tests pressed once and released, so they
  passed; the maintainer found it by clicking a motion lane twice. Tests now repeat the interaction after a full
  settle.

- **A mutation counts as caught only if a test failed, not if the file failed to load.** A QML test file with a
  compile error (an alias named `layer`, which `Item` already has) made every mutation look caught. Check the
  failure count per mutation: one or two real failures, not a missing test case.

- **Rerun the whole mutation set after editing tests, not just the new mutants.** Replacing a test by cutting the
  file between two function names also deleted a test that had been inserted in between; two mutants it had
  caught came back, which is how it was noticed. List the test functions before committing.

- **An item loses `activeFocus` when a child takes focus** (unless it is a FocusScope). "Close when the panel
  loses focus" written on the panel item closed it as soon as a slider inside was pressed. For "the user went
  elsewhere", watch the window (`Window.active`); and test a click inside, not only a focus change outside.

- **`WheelHandler` accepts only `PointerDevice.Mouse` by default, and Qt's Wayland plugin may report a wheel as
  a `TouchPad`.** Scrolling the pill's volume passed every offscreen test (QtTest's wheel is a mouse) and did
  nothing on niri: the handler declined each event. Set `acceptedDevices: PointerDevice.Mouse |
  PointerDevice.TouchPad`. To see why an input does nothing, run with
  `QT_LOGGING_RULES="qt.quick.handler.dispatch=true"`; it prints each handler that DECLINES. On niri,
  `nix shell nixpkgs#wlrctl -c wlrctl pointer move|scroll` drives the real pointer (the position persists).

- **`prop: prop` binds a property to itself.** In `QuickSettingsWindow { backend: backend }` the right-hand
  `backend` is the window's own property, not the id outside, so the panel got `undefined` and nothing failed
  loudly: tiles showed "Unavailable", which looked like a machine without hardware. Never give an id the name of a
  property it is assigned to; check wiring by asking the running shell (`ipc call quicksettings state`).

- **Headless sway has no pointer.** `swaymsg seat ... cursor press` succeeds but no client gets a click (seat
  capabilities 0), and `wlrctl` creates a virtual pointer only for one command. Test clicks offscreen; test
  wiring through IPC.

- **Reading a `color` property in JavaScript gives a live reference, not a copy** (Qt 6 value types): a "before"
  value read into a `var` changes with the property. Copy with `String(...)` when comparing before and after.

- **Quickshell offscreen cannot make a `PanelWindow`** ("No PanelWindow backend loaded"), and the whole config fails
  to load. Test windows under a headless sway (`WLR_BACKENDS=headless`); give it a short `XDG_RUNTIME_DIR`, because a
  Unix socket path over 108 bytes fails with "Unable to open wayland socket".

- **Publish readiness last.** BrightnessService set `available` before `device` and `maximum`, so anything reacting
  to `available` and calling `set()` would have written the minimum to no device. Set every field, then the flag.

- **Setting `Process.running = true` while it runs reruns it once, with the latest `command`, after it exits**
  (Quickshell 0.3.2, observed, not documented). A queue that relies only on that would work by accident; ours is
  explicit, and its mutant survives because of this.

- **A `{` in a comment above the imports breaks Quickshell's `qs.*` imports.** A test header comment holding
  `{ws}` made `import qs.common` fail with "module is not installed"; the same file without the brace loaded.
  Quickshell seems to read a file's header only up to the first brace. Keep braces out of leading comments.

- **`JsonAdapter` drops keys it does not declare when it writes** (Quickshell 0.3.2, probed). A settings file
  written back through it loses whatever a newer shell or the user added. The settings store (D45) parses and
  writes the text itself. Other `FileView` facts from the same probe: a missing file gives `loadFailed` with
  `FileViewError.FileNotFound` (and a warning unless `printErrors: false`); `setText` creates missing parent
  directories; a write to a read-only home-manager link fails with `PermissionDenied` through `saveFailed`; a
  `setText` issued inside `onLoaded` can be dropped ("got operation finished from dropped operation").

- **`FileView` writes are asynchronous, and two views on one file race.** In the settings test, the store's
  reset and the test's own edit landed in either order. Wait for one write to show on disk before the next.
  `watchChanges` on a file that does not exist yet never fires when it is created; read it again instead.

- **An `on<Property>Changed` handler can run before bindings that depend on the same property.** The popup
  stack's `onPopupsChanged` read `byId` (a binding on `popups`) and saw the old map, so a leaving card was never
  marked. In a change handler, compute from the property itself. Likewise Quickshell's
  `trackedNotifications` takes in a notification only after the `notification` handler that tracks it returns:
  work on the whole list (the cap on kept notifications) goes in `Qt.callLater`.

- **QtTest can leave a MouseArea hovered.** After `mouseClick` on a button and then elsewhere, the button's
  `containsMouse` stayed true even after `mouseMove` away. Test hover-dependent behavior on a fresh object.

- **A ListView on a JS array rebuilds every delegate on each change**, so add, remove and displaced transitions
  never play. The notification list keeps a ListModel of keys in step with the data (`NotificationRows.sync`:
  remove, move, insert) and looks the data up by key.

- **A ListView that shrinks at once skips its remove transition.** With `height: Math.min(contentHeight, max)`,
  removing a row shrinks the view in the same step, the removed delegate is out of view, and Qt destroys it
  without the transition (Qt 6.12, isolated in a scratch test). The notification list keeps the view at full
  height inside a clipping Item whose height animates.

- **Quickshell's inline reply placeholder is the action's text** (`inline-reply` with "Message" gives "Message"),
  not KDE's placeholder hint.

- **An object used as a map has a prototype:** `{}["constructor"]` is truthy, so an app named "constructor"
  grouped wrongly until the lookup compared `=== true` (and the grouping used `Object.create(null)`).

- **`busctl` takes a `-1` argument for an option.** Put `--` before `call` when sending a notification with
  the default timeout.

- **Quickshell does not re-emit `notification` for a replaced notification** (same id): the object updates in
  place. And `Notification.expireTimeout` is in ms, though documented as seconds (0.3.2, probed).

- **Quickshell runs headless.** `QT_QPA_PLATFORM=offscreen quickshell -p file.qml` (with WAYLAND_DISPLAY unset)
  loads a shell, runs FileView and timers, and exits on `Qt.exit()`; that is how tests/qs/ runs.

- **`Spring.snap()` settles the spring before it returns.** Handlers on `settled` (or anything bound to it) run in
  the middle of a restart: ShapeMorph cleared its morph data when the spring reported settled, so a morph started
  with `snap(0)` lost the data it had just been given. Set the data after `snap()` and the new `target`.

- **Measure with the plugins the session has.** An SVG image looked half the memory of a vector shape until the
  render showed blank squares: the test environment has no qtsvg plugin, so nothing was drawn or held.
  Look at the render before trusting a memory number.

- **A surviving mutant may be equivalent; prove it before adding tests.** Rounding a decagon of radius 1 instead of
  1/cos(18°) still gives a circle once normalized. When a mutant survives a strong check, search for inputs that
  tell the two versions apart (a script over all 35 x 35 morph pairs found cases for three mutants) and add those.

- **Write down interaction rules with examples as they are decided.** The grid's gap, resize and drop rules took
  three rounds with the maintainer; `docs/editable-grid.md` holds them with diagrams and the test for each, so
  nobody has to rediscover them from the code.

- **Drive a drag in fixed coordinates.** QtTest's `mouseMove(item, x, y)` maps from the item at the time of the
  call, so moving relative to the item being dragged compounds every step. The grid tests press on the item and
  then move in the TestCase's coordinates.

- **Before fixing a failing pixel test, print the pixels.** A "hole" in a filled icon was the corner of the test's
  sample square on the glyph's edge; dumping the sampled grid as text showed it in one run.

- **The first design is often wrong; test the attack.** The ownership guard, the weight test and the transparency
  test were all fixed by trying to break them.
- **Say what is unverified.** Every handoff names what was not tested and why (needs the maintainer's hardware or a
  real session). Do not let a long list of green checks imply it.
- **Do not tag what the maintainer already has.** If a tag was delivered, add a commit instead.

- **A Column places its children at the next polish, not when they are created** (settings app, October 2026).
  Code that measures a row right after a Repeater made it (scrolling to it with `mapToItem`) sees y = 0, and a
  test that clicks before the first frame clicks the wrong place. Call `forceLayout()` on the Columns before
  measuring; in tests, `waitForRendering(item)` after anything that builds rows. ListView is worse for tests:
  it makes only the delegates in view, so `findChild` misses the rest; use a Repeater for short lists.
- **A popup that belongs to a row is drawn under the rows of the next section** (settings app). `z` orders
  only siblings, so a later sibling Column covers it whatever its z. Put the popup at the top of the view, and
  its outside-click catcher above the content: a catcher underneath never sees a click on a Flickable.
- **Mutation-test with the one test file that covers the code** (`qtws.py test tst_name`): the whole QML suite
  takes about 70 s per mutant, one file a few seconds.
- **Qt's portal file dialog needs real Wayland and a moment** (D51). Under `QT_QPA_PLATFORM=offscreen` the platform
  theme is never used, so an offscreen check proves nothing; and right after start the xdgdesktopportal theme has
  not yet learned the portal's version, so a dialog opened then falls back to Qt's own. Check with `dbus-monitor
  --session "type='method_call',interface='org.freedesktop.portal.FileChooser'"` and open it a few seconds in.
- **`pkill -f PATTERN` from a shell kills that shell when its own command line contains PATTERN** (twice in
  October 2026: stopping a mutation batch killed the command doing it). Kill by PID (`pgrep` first, look, then
  `kill`), or make the pattern unable to match itself (`pkill -f "[m]ut.py"`).
- **`select()` on a buffered pipe misses data already read into the buffer.** A test that reads two messages
  through `proc.stdout` (buffered) and then waits on `select` hangs: the second one was buffered by the first
  read. Use `bufsize=0` and read exact byte counts.
- **unittest builds an assertion's message even when the assertion passes** (`assertTrue(x, "..." + f())` calls
  f every time). A message that waits on a process (`p.wait`, reading its stderr) hung every passing read of the
  C host's tests. Build costly messages only on failure: `if not x: self.fail(...)`.


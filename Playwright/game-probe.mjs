// The browser build of the port, played in Chromium and judged by the board: every input is a
// move the game must have made exactly as upstream's algorithm makes it. The board is read
// from the page's display list as settled cells (column, row, number) once nothing animates —
// never from pixel positions mid-animation — and compared with `expectedMove`, a line-for-line
// port of upstream's GameLogic.move (merges, the "moved" test against its misaligned snapshot,
// two 2-blocks spawned when at least two squares are blank). Flows:
//   launch               two 2-blocks on a fresh board; the board holds keyboard focus
//   arrows               ← → ↑ ↓ each verified against the reference, then until a merge, a
//                        swipe that changes nothing and a changes-nothing-yet-spawns swipe
//                        (upstream's quirk) have all been seen
//   new-game             the visible button resets the board to two 2-blocks, and the arrows
//                        still move it afterwards (regression: a click used to drop focus)
//   mouse-drag           a mouse drag in each direction is a move (regression)
//   touch-drag           a finger drag (real touch events over CDP) in each direction
//   layout               portrait, phone landscape and tablet landscape: the banner as
//                        upstream shows it, the New Game button clear of the grid
//   release-boundary     the published build ignores a harness query in its URL (two random
//                        blocks, not the board named there)
//   dom-shortcut         what a page can and cannot see of ⌘N/Ctrl+N (recorded, not a pass)
//   controlled-*         on the HARNESS build only (`scripts/build-web.sh --harness`, served
//                        separately and passed as --harness <url>): the page's URL lays out
//                        the board and names where new blocks land through the model's two
//                        test seams, so both no-op variants and the no-spawn-under-two-blanks
//                        rule are asserted on exact boards, every run. The default page above
//                        is the published build and runs with upstream's random source; its
//                        arrows flow still looks for the same cases and reports what it saw.
// Usage: node game-probe.mjs http://127.0.0.1:8791/index.html [--harness http://127.0.0.1:8792/index.html] [--out ../.build/probe]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const args = process.argv.slice(2);
const url = args.find(a => a.startsWith('http'));
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = option('--out', join(root, '.build', 'probe'));
const harness = option('--harness', null);
if (!url) { console.error('usage: node game-probe.mjs <url> [--out dir]'); process.exit(2); }
mkdirSync(out, { recursive: true });

const git = (command) => { try { return execSync(command, { cwd: root, encoding: 'utf8' }).trim(); } catch { return null; } };
const report = {
  url, harness_url: harness, started: new Date().toISOString(),
  commit: git('git rev-parse HEAD'), working_tree: git('git status --porcelain') ? 'dirty' : 'clean',
  // What differs from the commit when dirty (paths, `git status --porcelain` form), so a
  // generated or tool-rewritten file is told apart from a source change.
  working_tree_changes: (git('git status --porcelain') || '').split('\n').filter(Boolean),
  library: git('git -C vendor/swiftui-web rev-parse HEAD'),
  flows: [], screenshots: [], problems: [], full_app_pass: false,
};
const flow = (name, outcome, detail) => { report.flows.push({ name, outcome, ...detail }); console.log(`${name}: ${outcome}${detail && detail.note ? ' — ' + detail.note : ''}`); };
const problem = (text) => { report.problems.push(text); console.log('PROBLEM ' + text); };

// MARK: upstream's algorithm (GameLogic.move), on a board of 4 rows of numbers (0 = blank)
const DIRECTIONS = ['left', 'right', 'up', 'down'];
function expectedMove(board, direction) {
  const next = board.map(row => row.slice());
  const axis = direction === 'left' || direction === 'right';
  const at = (b, row, col) => axis ? b[row][col] : b[col][row];
  const set = (b, row, col, value) => { if (axis) b[row][col] = value; else b[col][row] = value; };
  let moved = false;
  for (let row = 0; row < 4; row++) {
    const snapshot = []; let compact = [];
    for (let col = 0; col < 4; col++) {
      const value = at(board, row, col);
      if (value) { snapshot.push(value); compact.push(value); }
      snapshot.push(0);   // upstream appends nil after every square, aligned or not
    }
    const reverse = direction === 'down' || direction === 'right';
    if (reverse) compact.reverse();
    const merged = [];
    for (const value of compact) {
      const last = merged[merged.length - 1];
      if (last && !last.merged && last.value === value) { merged.pop(); merged.push({ value: value * 2, merged: true }); }
      else merged.push({ value, merged: false });
    }
    compact = merged.map(m => m.value);
    if (reverse) compact.reverse();
    const line = compact.slice();
    while (line.length < 4) { if (direction === 'left' || direction === 'up') line.push(0); else line.unshift(0); }
    line.forEach((value, i) => { if (snapshot[i] !== value) moved = true; set(next, row, i, value); });
  }
  return { board: next, moved };
}
const blanks = (board) => board.flat().filter(v => v === 0).length;
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const show = (board) => board.map(r => r.map(v => String(v || '.').padStart(4)).join('')).join(' |');

// A board after a move must be the reference's, plus — when the reference says "moved" and
// two or more squares are blank — exactly two new 2s on squares the reference left blank.
function judge(before, after, direction) {
  const expected = expectedMove(before, direction);
  const spawns = [];
  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) {
    if (expected.board[r][c] !== after[r][c]) {
      if (expected.board[r][c] === 0 && after[r][c] === 2) spawns.push([c, r]);
      else return { ok: false, why: `cell (${c},${r}) is ${after[r][c]}, expected ${expected.board[r][c]}` };
    }
  }
  const shouldSpawn = expected.moved && blanks(expected.board) >= 2;
  if (shouldSpawn && spawns.length !== 2) return { ok: false, why: `${spawns.length} new blocks, expected 2 (upstream spawns two)` };
  if (!shouldSpawn && spawns.length !== 0) return { ok: false, why: `${spawns.length} new blocks, expected none` };
  const merges = before.flat().filter(Boolean).length - expected.board.flat().filter(Boolean).length;
  return { ok: true, moved: expected.moved, changed: !same(before, expected.board), merges, spawns };
}

// MARK: the page
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true });
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));
let shots = 0;
const shot = async (name) => { const file = `${String(++shots).padStart(2, '0')}-${name}.png`; await page.screenshot({ path: join(out, file) }); report.screenshots.push(file); };

const settle = async () => {
  await page.waitForFunction(() => !window.__swiftuiwebDebug.animating(), null, { timeout: 10000 });
  await page.waitForTimeout(150);
  await page.waitForFunction(() => !window.__swiftuiwebDebug.animating(), null, { timeout: 10000 });
};
// The grid is the 320×320 rectangle in upstream's grid colour; a block's number is the text
// drawn inside it, its cell from the 65 + 12 pitch.
const readBoard = () => page.evaluate(() => {
  const list = window.__swiftuiwebDebug.displayList();
  const grid = list.map(c => c.match(/^fillRect\((-?[\d.]+), (-?[\d.]+), 320, 320\) #B8A8A1/)).find(Boolean);
  if (!grid) return null;
  const [x0, y0] = [Number(grid[1]), Number(grid[2])];
  const board = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
  for (const c of list) {
    const m = c.match(/^drawText\("(\d+)" .* at (-?[\d.]+),(-?[\d.]+)/);
    if (!m) continue;
    const x = Number(m[2]) - x0, y = Number(m[3]) - y0;
    if (x < 0 || y < 0 || x >= 320 || y >= 320) continue;
    const col = Math.floor(x / 77), row = Math.floor(y / 77);
    if (board[row][col]) throw new Error(`two numbers in cell (${col},${row})`);
    board[row][col] = Number(m[1]);
  }
  return { board, grid: { x: x0, y: y0, width: 320, height: 320 } };
});
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
const focusedRole = () => page.evaluate(() => { const a = document.activeElement; return a ? (a.getAttribute('role') || a.tagName.toLowerCase()) : null; });
const buttonRect = () => page.evaluate(() => { const e = Array.from(document.querySelectorAll('#app *')).find(e => e.getAttribute('aria-label') === 'New Game'); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; });
const clickNewGame = async () => { const r = await buttonRect(); if (!r) throw new Error('no New Game button'); await page.mouse.click(r.x + r.width / 2, r.y + r.height / 2); };

// One input, judged.
async function play(name, direction, input) {
  const before = (await readBoard()).board;
  await input();
  await settle();
  const after = (await readBoard()).board;
  const verdict = judge(before, after, direction);
  if (!verdict.ok) problem(`${name} ${direction}: ${verdict.why}\n  before ${show(before)}\n  after  ${show(after)}`);
  return verdict;
}
const arrow = { left: 'ArrowLeft', right: 'ArrowRight', up: 'ArrowUp', down: 'ArrowDown' };
const mouseDrag = (grid, direction) => async () => {
  const cx = grid.x + 160, cy = grid.y + 160, dx = { left: -1, right: 1, up: 0, down: 0 }[direction] * 120, dy = { left: 0, right: 0, up: -1, down: 1 }[direction] * 120;
  await page.mouse.move(cx, cy); await page.mouse.down();
  for (let i = 1; i <= 12; i++) { await page.mouse.move(cx + dx * i / 12, cy + dy * i / 12); await page.waitForTimeout(16); }
  await page.mouse.up();
};
// A finger on the page itself: Chromium's touch events through CDP (Input.dispatchTouchEvent),
// which reach the canvas's touch/pointer listeners as a real finger's do — not the host's
// scripted-drag debug hook, which starts below the DOM.
const touchDrag = (grid, direction) => async () => {
  const cx = grid.x + 160, cy = grid.y + 160, dx = { left: -1, right: 1, up: 0, down: 0 }[direction] * 120, dy = { left: 0, right: 0, up: -1, down: 1 }[direction] * 120;
  const touch = async (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] });
  await touch('touchStart', cx, cy);
  for (let i = 1; i <= 12; i++) { await touch('touchMove', cx + dx * i / 12, cy + dy * i / 12); await page.waitForTimeout(16); }
  await touch('touchEnd', cx + dx, cy + dy);
};

try {
  await page.goto(url);
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await settle();

  // launch
  {
    const read = await readBoard();
    const numbers = read ? read.board.flat().filter(Boolean) : [];
    const focused = await focusedRole();
    const ok = read && same(numbers, [2, 2]) && focused === 'group';
    flow('launch', ok ? 'passed' : 'failed', { board: read && read.board, focused, note: read ? `${numbers.length} blocks ${JSON.stringify(numbers)}, focus on ${focused}` : 'no grid drawn' });
    if (!ok) problem('launch: expected two 2-blocks on a focused board');
    await shot('launch');
  }

  // arrows: every direction, then directions chosen from what the reference predicts for the
  // board on screen, until a merge, a swipe that leaves the board as it is (no block moves,
  // so upstream spawns nothing) and a swipe that moves nothing but still spawns (upstream's
  // misaligned "moved" test) have all been seen
  {
    let merges = 0, unchanged = 0, spawnedUnchanged = 0, failures = 0, freshBoards = 0;
    // A swipe that moves nothing needs every line on its axis to hold at most one block, or
    // blocks already against that edge: mid-game, with two blocks spawned per move, that
    // never comes; a fresh two-block board offers it about one time in five.
    let noopMoves = 0;
    for (let tries = 0; unchanged === 0 && tries < 40 && failures === 0; tries++) {
      if (tries > 0) { await clickNewGame(); await settle(); }
      freshBoards++;
      const board = (await readBoard()).board;
      const noop = DIRECTIONS.find(d => !expectedMove(board, d).moved);
      if (!noop) continue;
      const verdict = await play('arrow (nothing moves)', noop, () => page.keyboard.press(arrow[noop]));
      noopMoves++;
      if (!verdict.ok) failures++; else if (!verdict.moved) unchanged++;
    }
    // The four directions once each from where the no-op search left the board, then short
    // games: a fresh board, up to eight moves steered by what the reference predicts (first a
    // swipe that moves nothing yet spawns — a compacted line of unequal blocks with two blanks
    // left, which a sparse board offers and a full one does not — then a merge, then any
    // change), a new game when a board fills, until a merge and that spawn have been seen.
    let moves = noopMoves;
    for (const direction of ['left', 'down', 'right', 'up']) {
      const verdict = await play('arrow', direction, () => page.keyboard.press(arrow[direction]));
      moves++;
      if (!verdict.ok) { failures++; continue; }
      merges += verdict.merges;
      if (!verdict.moved) unchanged++;
      if (verdict.moved && !verdict.changed && verdict.spawns.length === 2) spawnedUnchanged++;
    }
    for (let game = 0; game < 25 && (merges === 0 || spawnedUnchanged === 0) && failures === 0; game++) {
      await clickNewGame(); await settle(); freshBoards++;
      for (let i = 0; i < 8 && (merges === 0 || spawnedUnchanged === 0) && failures === 0; i++) {
        const board = (await readBoard()).board;
        const predictions = DIRECTIONS.map(d => ({ d, ...expectedMove(board, d) })).map(p => ({ ...p, changed: !same(board, p.board) }));
        const pick = (spawnedUnchanged === 0 && predictions.find(p => p.moved && !p.changed && blanks(p.board) >= 2))
          || (merges === 0 && predictions.find(p => p.board.flat().filter(Boolean).length < board.flat().filter(Boolean).length))
          || predictions.find(p => p.changed && blanks(p.board) >= 2);
        if (!pick) break;
        const verdict = await play('arrow', pick.d, () => page.keyboard.press(arrow[pick.d]));
        moves++;
        if (!verdict.ok) { failures++; break; }
        merges += verdict.merges;
        if (!verdict.moved) unchanged++;
        if (verdict.moved && !verdict.changed && verdict.spawns.length === 2) spawnedUnchanged++;
      }
    }
    // Every move must have matched the reference and a merge must have been seen; the two
    // no-op variants are reported here as found by chance and asserted on exact boards in the
    // controlled flows (with --harness), since a random game may not offer them.
    const ok = failures === 0 && merges > 0 && moves >= 4;
    flow('arrows', ok ? 'passed' : 'failed', { moves, merges, unchanged, spawnedUnchanged, freshBoards, note: `${moves} moves judged, ${merges} merges, ${unchanged} swipe(s) that left the board alone (after ${freshBoards} fresh boards), ${spawnedUnchanged} that moved nothing yet spawned (upstream's quirk) — by chance; see controlled-*` });
    await shot('arrows');
  }

  // new-game: the button, then the arrows still work (regression)
  {
    const before = (await readBoard()).board;
    await clickNewGame();
    await settle();
    const fresh = (await readBoard()).board;
    const numbers = fresh.flat().filter(Boolean);
    const focused = await focusedRole();
    let ok = same(numbers, [2, 2]) && !same(before, fresh);
    if (!ok) problem(`new-game: board after the button ${show(fresh)} (before ${show(before)})`);
    let moved = 0;
    for (const direction of DIRECTIONS) {
      const verdict = await play('after new game, arrow', direction, () => page.keyboard.press(arrow[direction]));
      if (!verdict.ok) ok = false; else if (verdict.changed) moved++;
    }
    if (moved === 0) { ok = false; problem('new-game: no arrow moved the fresh board'); }
    flow('new-game', ok ? 'passed' : 'failed', { focusedAfterClick: focused, arrowsThatMoved: moved, note: `two 2-blocks after the button, focus on ${focused}, ${moved} of 4 arrows moved the board` });
    await shot('new-game');
  }

  // mouse-drag and touch-drag: each direction once, judged
  for (const [name, make] of [['mouse-drag', mouseDrag], ['touch-drag', touchDrag]]) {
    let ok = true, changed = 0;
    for (const direction of DIRECTIONS) {
      const grid = (await readBoard()).grid;
      const verdict = await play(name, direction, make(grid, direction));
      if (!verdict.ok) ok = false; else if (verdict.changed) changed++;
    }
    if (changed === 0) { ok = false; problem(`${name}: no drag moved the board`); }
    flow(name, ok ? 'passed' : 'failed', { dragsThatMoved: changed, note: `4 drags judged, ${changed} moved the board` });
    await shot(name);
  }

  // layout: upstream's traits (banner above 550 pt tall in portrait, beyond 720 pt wide in
  // landscape), the grid centred, the button clear of the grid
  {
    const cases = [[390, 844, true], [667, 375, false], [1024, 768, true], [375, 500, false]];
    const results = [];
    for (const [width, height, banner] of cases) {
      await page.setViewportSize({ width, height });
      await settle();
      const read = await readBoard();
      const button = await buttonRect();
      const hasBanner = (await texts()).includes('2048');
      const pageHeight = height - 28;   // the credit line below the game
      const centred = read && Math.abs(read.grid.x + 160 - width / 2) <= 1 && Math.abs(read.grid.y + 160 - pageHeight / 2) <= 1;
      const clear = read && button && (button.y >= read.grid.y + 320 || button.y + button.height <= read.grid.y || button.x >= read.grid.x + 320 || button.x + button.width <= read.grid.x);
      const ok = !!read && hasBanner === banner && centred && clear;
      results.push({ width, height, banner: hasBanner, centred, buttonClearOfGrid: clear, ok });
      if (!ok) problem(`layout ${width}×${height}: banner ${hasBanner} (expected ${banner}), centred ${centred}, button clear ${clear}`);
      await shot(`layout-${width}x${height}`);
    }
    flow('layout', results.every(r => r.ok) ? 'passed' : 'failed', { cases: results, note: results.map(r => `${r.width}×${r.height} ${r.ok ? 'ok' : 'FAIL'}`).join(', ') });
    await page.setViewportSize({ width: 390, height: 844 });
    await settle();
  }

  // release-boundary: the published build with a harness query in its URL starts an
  // ordinary game — two 2-blocks from upstream's random source, not the board in the URL.
  {
    const laid = [[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [32, 64, 128, 0]];
    await page.goto(`${url}?chooser=first&board=${laid.flat().join(',')}`);
    await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
    await settle();
    const read = (await readBoard()).board;
    const numbers = read.flat().filter(Boolean);
    const ok = same(numbers, [2, 2]) && !same(read, laid);
    if (!ok) problem(`release-boundary: the published build honoured a harness query: ${show(read)}`);
    flow('release-boundary', ok ? 'passed' : 'failed', { board: read, note: `published build with ?board=…&chooser=first in its URL: ${numbers.length} blocks ${JSON.stringify(numbers)}, the URL's board ignored` });
    await page.goto(url);
    await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
    await settle();
  }

  // dom-shortcut: a synthetic ⌘N/Ctrl+N reaches the page's shortcut handler here, but a real
  // browser keeps those for its own New Window and never delivers them — recorded so the
  // button, not the shortcut, is the browser's restart; not counted as a pass.
  {
    const before = (await readBoard()).board;
    await page.keyboard.press(process.platform === 'darwin' ? 'Meta+n' : 'Control+n');
    await settle();
    const after = (await readBoard()).board;
    flow('dom-shortcut', 'recorded', { syntheticShortcutResetTheBoard: !same(before, after), note: `synthetic ⌘N/Ctrl+N ${same(before, after) ? 'did not reach' : 'reached'} the game; a real browser reserves it (New Window), so the visible button is the restart` });
  }

  // controlled-*: the harness build, exact boards through the seams (chooser=first: new blocks
  // land on the first blank, then the last)
  if (harness) {
    const open = async (board) => {
      await page.goto(`${harness}?chooser=first&board=${board.flat().join(',')}`);
      await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
      await settle();
      const read = (await readBoard()).board;
      if (!same(read, board)) throw new Error(`the harness did not lay out the board: ${show(read)}`);
    };
    const exact = async (name, direction, expected) => {
      await page.keyboard.press(arrow[direction]);
      await settle();
      const after = (await readBoard()).board;
      const ok = same(after, expected);
      if (!ok) problem(`${name}: after ${direction} ${show(after)}, expected ${show(expected)}`);
      return ok;
    };
    const cases = [
      // Nothing moves, nothing spawns: one block already against the edge, every line on the
      // axis holding at most one block.
      ['controlled-no-move', [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], [
        ['left', [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]],
        ['up', [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]],
      ]],
      // Nothing moves, yet two blocks spawn (upstream's misaligned "moved" test): a compacted
      // line of unequal blocks swiped toward its edge; the same board swiped across the other
      // axis moves nothing and spawns nothing.
      ['controlled-no-move-spawn', [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], [
        ['left', [[2, 4, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]]],
      ]],
      ['controlled-no-move-spawn-other-axis', [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], [
        ['up', [[2, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]],
      ]],
      // A move with one blank left: no block spawns.
      ['controlled-no-spawn-under-two-blanks', [[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [32, 64, 128, 0]], [
        ['right', [[2, 4, 8, 16], [32, 64, 128, 256], [2, 4, 8, 16], [0, 32, 64, 128]]],
      ]],
      // Merges once per pair, leading pair first; the spawns on the first and the last blank.
      ['controlled-merge', [[2, 2, 2, 0], [4, 2, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0]], [
        ['left', [[4, 2, 2, 0], [4, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]]],
      ]],
    ];
    for (const [name, board, steps] of cases) {
      let ok = true;
      try {
        await open(board);
        for (const [direction, expected] of steps) ok = (await exact(name, direction, expected)) && ok;
      } catch (error) { ok = false; problem(`${name}: ${error.message}`); }
      flow(name, ok ? 'passed' : 'failed', { controlled: true, board, note: `harness build, board laid out through the seams, chooser=first: ${steps.map(([d]) => d).join(', ')} ${ok ? 'exact' : 'MISMATCH'}` });
      await shot(name);
    }
    // The harness's New Game lands the two blocks where the chooser says: a known board.
    {
      await clickNewGame(); await settle();
      const fresh = (await readBoard()).board;
      const ok = same(fresh, [[2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2]]);
      if (!ok) problem(`controlled-new-game: ${show(fresh)}`);
      flow('controlled-new-game', ok ? 'passed' : 'failed', { controlled: true, note: 'harness build, chooser=first: the first and the last blank' });
    }
  } else {
    flow('controlled', 'skipped', { note: 'no --harness url: the exact-board cases did not run' });
  }

  if (consoleErrors.length) problem('console errors: ' + consoleErrors.join(' | '));
} catch (error) {
  problem('probe: ' + (error.stack || error.message));
} finally {
  await browser.close();
}
const judged = report.flows.filter(f => f.outcome !== 'recorded');
// Passing needs the published page's flows and the controlled flows on the harness build.
report.full_app_pass = judged.length >= 6 && judged.every(f => f.outcome === 'passed') && report.flows.some(f => f.name === 'controlled-no-move-spawn') && report.problems.length === 0;
report.finished = new Date().toISOString();
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
console.log(`game probe: ${report.full_app_pass ? 'PASSED' : 'FAILED'} (${join(out, 'report.json')})`);
process.exit(report.full_app_pass ? 0 : 1);

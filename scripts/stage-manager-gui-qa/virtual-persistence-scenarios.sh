#!/bin/bash
set -euo pipefail
ym_persistence_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_persistence_source/guard.sh"
ym_persistence_app="${1:?missing product app}"
ym_persistence_helpers="${2:?missing helper directory}"
ym_persistence_evidence="${3:?missing evidence directory}"
mkdir -p "$ym_persistence_evidence"
python3 - "$ym_persistence_app" "$ym_persistence_helpers" "$ym_persistence_evidence" "$ym_persistence_source" <<'PY'
import json, os, pathlib, signal, subprocess, sys, threading, time, traceback, uuid

# Defense in depth: this controller can never be used against a personal Mac.
assert os.environ.get('GITHUB_ACTIONS') == 'true'
assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
assert sys.platform == 'darwin'
app, helper_dir, evidence_dir, source_dir = map(pathlib.Path, sys.argv[1:])
evidence_dir.mkdir(parents=True, exist_ok=True)
helper = helper_dir / 'virtual-persistence-actions'
fixture_app = helper_dir / 'VirtualPersistenceFixture.app'
fixture_dir = evidence_dir / 'fixture'
fixture_dir.mkdir(exist_ok=True)
state_file = fixture_dir / 'fixture-state.json'
product_pid = None
fixture_process = None
monitor_stop = threading.Event()
monitor_thread = None
records, checks, actions = [], [], []
started = time.monotonic()

def write(name, value):
    (evidence_dir / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

def run(argv, timeout=20, check=True):
    environment = os.environ.copy()
    if pathlib.Path(str(argv[0])).name == 'panel-menu-actions':
        environment['YM_QA_MENU_FAILURE_DIRECTORY'] = str(evidence_dir / 'menu-failures')
    result = subprocess.run([str(x) for x in argv], capture_output=True, text=True, timeout=timeout, env=environment)
    if check and result.returncode:
        raise RuntimeError(f'helper failed ({result.returncode}): {pathlib.Path(str(argv[0])).name} {argv[1:]}\n{result.stdout}\n{result.stderr}')
    return result

def call(*args):
    result = run([helper, *args])
    return json.loads(result.stdout)

def parse_close_receipt(stdout, expected_pid):
    # osascript prints its last returned AX element before the shell helper's
    # final JSON receipt. Keep that raw output separately; parse only the
    # explicit final receipt and verify its ownership/action contract.
    lines = [line for line in stdout.splitlines() if line.strip()]
    if not lines:
        raise ValueError('close helper did not return a receipt')
    receipt = json.loads(lines[-1])
    if not isinstance(receipt, dict) or receipt.get('pid') != expected_pid or receipt.get('action') != 'close':
        raise ValueError('close helper returned a mismatched receipt')
    return receipt

def wait_for(description, callback, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = callback()
        if value:
            return value
        time.sleep(.2)
    raise AssertionError('timed out: ' + description)

def check(name, value, detail=None):
    checks.append({'name': name, 'passed': bool(value), 'detail': detail})
    if not value:
        raise AssertionError(name + (': ' + str(detail) if detail is not None else ''))

def panel_state():
    return call('panel-state', product_pid)

def panel_visible(state):
    return any(w.get('title') == 'yomado' and w.get('onscreen') for w in state['windows'])

def wait_policy(policy, visible):
    def ready():
        s = panel_state()
        return s if s['activationPolicy'] == policy and panel_visible(s) == visible else None
    return wait_for(f'policy {policy}, panel visible={visible}', ready)

def action(command):
    value = call(command, product_pid)
    actions.append(value)
    time.sleep(.35)

def open_panel():
    actions.append(json.loads(run([helper_dir / 'panel-menu-actions', product_pid, 'open']).stdout))
    time.sleep(.25)
    actions.append(json.loads(run([helper_dir / 'panel-menu-actions', product_pid, 'select-open-panel']).stdout))
    return wait_policy(0, True)

def fixture_state():
    try:
        return json.loads(state_file.read_text())
    except (OSError, json.JSONDecodeError):
        return None

def place_fixture(display_id):
    value = {'nonce': str(uuid.uuid4()), 'command': 'place-on-existing-display', 'displayID': display_id}
    temporary = fixture_dir / 'command.tmp'
    temporary.write_text(json.dumps(value))
    temporary.replace(fixture_dir / 'command.json')
    wait_for('fixture accepted placement', lambda: (fixture_state() or {}).get('placementNonce') == value['nonce'])

def sample(display_id, label=None):
    args = ['sample', product_pid, fixture_process.pid, display_id, state_file]
    if label:
        args.append(evidence_dir / (label + '.png'))
    value = call(*args)
    if label:
        value['label'] = label
        write(label + '.json', value)
    return value

def contains(frame, inner):
    x,y,w,h = frame
    a,b,c,d = inner
    return a >= x and b >= y and a+c <= x+w and b+d <= y+h

def monitor(display_id):
    deadline = time.monotonic() + 150
    with (evidence_dir / 'continuity.jsonl').open('w') as stream:
        while not monitor_stop.is_set() and time.monotonic() < deadline:
            try:
                # Each call is a fresh observer process: no process-local CG
                # mode inventory cache can hide a destruction/recreation.
                record = sample(display_id)
            except Exception as error:
                record = {'error': str(error), 'monotonic': time.monotonic()}
            records.append(record)
            stream.write(json.dumps(record, ensure_ascii=False) + '\n'); stream.flush()
            monitor_stop.wait(.4)

def assert_sample(record, initial, baseline, virtual):
    assert record['productPID'] == initial['productPID']
    assert record['fixturePID'] == initial['fixturePID']
    by_id = {d['id']: d for d in record['displays']}
    assert len(by_id) == len(baseline) + 1
    for original in baseline:
        assert by_id.get(original['id']) == original, 'original guest output changed'
    assert by_id.get(virtual['id']) == virtual, 'virtual output identity/topology changed'
    assert virtual['active'] and not virtual['inMirrorSet'] and virtual['mirrors'] == 0
    assert record['fixtureWindow']['id'] == initial['fixtureWindow']['id']
    assert record['fixtureWindow']['bounds'] == initial['fixtureWindow']['bounds'], 'fixture moved'
    assert record['fixtureWindow']['onscreen'], 'fixture ceased to render onscreen'
    assert contains(virtual['bounds'], record['fixtureWindow']['bounds'])

def assert_regular_panel(record, initial):
    assert record['productPID'] == initial['productPID'], 'product process changed'
    assert record['activationPolicy'] == 0, 'product has not returned to Regular'
    panels = [w for w in record['productWindows'] if w.get('title') == 'yomado' and w.get('onscreen')]
    assert len(panels) == 1, 'expected exactly one visible product control panel'
    assert panels[0]['id'] == initial['productPanelWindowID'], 'product control panel was recreated'

try:
    # The earlier test phase must finish and release its product instance.
    existing = run([helper, 'pid', 'dev.chekusu.yomado'], check=False)
    check('no preexisting product process', existing.returncode != 0)
    baseline = call('inventory')
    write('baseline-displays.json', baseline)
    check('guest baseline has exactly one main output', sum(d['main'] for d in baseline) == 1)
    run(['/usr/bin/open', '-n', '--stdout', evidence_dir / 'product.stdout', '--stderr', evidence_dir / 'product.stderr', app])
    def find_product():
        found = run([helper, 'pid', 'dev.chekusu.yomado'], check=False)
        return int(found.stdout.strip()) if found.returncode == 0 else None
    product_pid = wait_for('new owned product process', find_product)
    write('panel-before-create.json', wait_policy(0, True))
    fixture_env = os.environ.copy()
    fixture_env['YM_QA_PERSISTENCE_DIRECTORY'] = str(fixture_dir)
    fixture_process = subprocess.Popen([str(fixture_app / 'Contents/MacOS/VirtualPersistenceFixture')], env=fixture_env,
                                     stdout=(evidence_dir / 'fixture.stdout').open('w'),
                                     stderr=(evidence_dir / 'fixture.stderr').open('w'))
    wait_for('live fixture', lambda: (fixture_state() or {}).get('pid') == fixture_process.pid)
    open_panel()
    # This is the unchanged product's real UI. The fixture never creates a
    # CGVirtualDisplay and this harness has no display-configuration API.
    action('add-menu')
    action('new-display')
    initial_ids = {d['id'] for d in baseline}
    def discover():
        current = call('inventory')
        new = [d for d in current if d['id'] not in initial_ids]
        return new[0] if len(new) == 1 and new[0]['active'] and 'mode' in new[0] else None
    virtual = wait_for('product-created extended output', discover)
    time.sleep(2)
    by_id = {d['id']: d for d in call('inventory')}
    check('creation preserves original outputs', all(by_id.get(d['id']) == d for d in baseline))
    virtual = by_id[virtual['id']]
    check('new output is extended and not main', not virtual['main'] and not virtual['inMirrorSet'] and virtual['mirrors'] == 0)
    check('new display has a stable UUID', bool(virtual.get('uuid')))
    place_fixture(virtual['id'])
    open_panel()
    wait_for('fixture wholly inside virtual screen', lambda: contains(virtual['bounds'], sample(virtual['id'])['fixtureWindow']['bounds']))
    initial = sample(virtual['id'], 'initial-on-virtual')
    initial_panels = [w for w in initial['productWindows'] if w.get('title') == 'yomado' and w.get('onscreen')]
    check('initial product has exactly one visible control panel', len(initial_panels) == 1)
    initial['productPanelWindowID'] = initial_panels[0]['id']
    write('initial-on-virtual.json', initial)
    assert_regular_panel(initial, initial)
    assert_sample(initial, initial, baseline, virtual)
    check('initial actual pixels are nonuniform', initial['image']['distinctBytes'] > 8)
    write('owned-processes.json', {'productPID': product_pid, 'fixturePID': fixture_process.pid,
                                 'createdDisplayID': virtual['id'], 'createdDisplayUUID': virtual['uuid']})
    monitor_thread = threading.Thread(target=monitor, args=(virtual['id'],), daemon=True)
    monitor_thread.start()
    intervals = []
    for cycle in range(1, 4):
        close_result = run(['/bin/bash', source_dir / 'close-owned-panel.sh', helper_dir, product_pid])
        (evidence_dir / f'cycle-{cycle}-close.stdout').write_text(close_result.stdout)
        (evidence_dir / f'cycle-{cycle}-close.stderr').write_text(close_result.stderr)
        actions.append(parse_close_receipt(close_result.stdout, product_pid))
        write(f'cycle-{cycle}-closed-panel.json', wait_policy(1, False))
        before = sample(virtual['id'], f'cycle-{cycle}-accessory-before')
        time.sleep(3)
        after = sample(virtual['id'], f'cycle-{cycle}-accessory-after')
        assert_sample(before, initial, baseline, virtual)
        assert_sample(after, initial, baseline, virtual)
        check(f'cycle {cycle}: remained Accessory', before['activationPolicy'] == after['activationPolicy'] == 1)
        check(f'cycle {cycle}: fixture timer continued', after['fixtureState']['counter'] - before['fixtureState']['counter'] >= 6)
        check(f'cycle {cycle}: actual fixture pixels changed', before['image']['fixtureSHA256'] != after['image']['fixtureSHA256'])
        check(f'cycle {cycle}: capture nonuniform', min(before['image']['distinctBytes'], after['image']['distinctBytes']) > 8)
        reopened = open_panel()
        write(f'cycle-{cycle}-reopened-panel.json', reopened)
        final = sample(virtual['id'], f'cycle-{cycle}-regular-after')
        assert_sample(final, initial, baseline, virtual)
        assert_regular_panel(final, initial)
        check(f'cycle {cycle}: same product panel remains visible', True, initial['productPanelWindowID'])
        check(f'cycle {cycle}: actual status-menu reopened Regular panel', final['activationPolicy'] == 0)
        intervals.append({'cycle': cycle, 'accessoryStart': before['uptime'], 'accessoryEnd': after['uptime'],
                          'counterDelta': after['fixtureState']['counter'] - before['fixtureState']['counter']})
    # Rename is reached from the actual card management menu after a status
    # menu reopen. The status menu itself has no direct Rename command.
    action('manage-menu')
    action('rename')
    def rename_sheet():
        current = panel_state()
        return current if any(n['role'] == 'AXSheet' for n in current['ax']) else None
    write('rename-sheet.json', wait_for('rename sheet', rename_sheet))
    action('cancel-rename')
    def no_sheet():
        current = panel_state()
        return current if not any(n['role'] == 'AXSheet' for n in current['ax']) else None
    write('rename-cancelled.json', wait_for('rename sheet dismissed', no_sheet))
    cancelled = sample(virtual['id'], 'after-rename-cancel')
    assert_sample(cancelled, initial, baseline, virtual)
    assert_regular_panel(cancelled, initial)
    check('rename cancellation preserves the same visible product panel', True, initial['productPanelWindowID'])
    check('rename cancelled without display/window changes', cancelled['activationPolicy'] == 0)
    monitor_stop.set(); monitor_thread.join(timeout=25)
    check('continuity observer completed', not monitor_thread.is_alive())
    check('continuity observer has meaningful duration', len(records) >= 20, len(records))
    for record in records:
        check('continuity sample has no observation error', 'error' not in record, record.get('error'))
        assert_sample(record, initial, baseline, virtual)
    for interval in intervals:
        subset = [r for r in records if interval['accessoryStart'] <= r['uptime'] <= interval['accessoryEnd']]
        check(f"cycle {interval['cycle']}: continuous accessory observations", len(subset) >= 3 and all(r['activationPolicy'] == 1 for r in subset), len(subset))
    write('summary.json', {'passed': True, 'checks': checks, 'cycles': intervals, 'continuousSamples': len(records),
                          'elapsedSeconds': time.monotonic() - started,
                          'scope': 'unchanged production UI creation and panel lifecycle; actual virtual-display pixels and test fixture continuity',
                          'notClaimed': ['independent input', 'locked-session operation', 'physical DisplayLink coverage', 'production app editing input'],
                          'fixturePlacement': 'fixture moves only its own test window onto the existing product-created display'})
    print('PASS: real product virtual display and fixture rendering persisted through three panel close/reopen cycles.', flush=True)
except BaseException as error:
    write('summary.json', {'passed': False, 'error': str(error), 'traceback': traceback.format_exc(),
                          'checks': checks, 'elapsedSeconds': time.monotonic() - started})
    if product_pid:
        try:
            write('failure-panel-state.json', panel_state())
        except Exception:
            pass
    raise
finally:
    monitor_stop.set()
    if monitor_thread:
        monitor_thread.join(timeout=25)
    write('actions.json', actions)
    if fixture_process and fixture_process.poll() is None:
        fixture_process.terminate()
        try:
            fixture_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            fixture_process.kill(); fixture_process.wait(timeout=5)
    if product_pid:
        found = run([helper, 'pid', 'dev.chekusu.yomado'], check=False)
        if found.returncode == 0 and found.stdout.strip() == str(product_pid):
            os.kill(product_pid, signal.SIGTERM)
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                current = run([helper, 'pid', 'dev.chekusu.yomado'], check=False)
                if current.returncode != 0:
                    break
                time.sleep(.2)
        try:
            final_inventory = wait_for('guest topology restored after owned product cleanup',
                                       lambda: call('inventory') == baseline, seconds=10)
            write('cleanup.json', {'passed': bool(final_inventory), 'displays': call('inventory')})
        except Exception as cleanup_error:
            write('cleanup.json', {'passed': False, 'error': str(cleanup_error)})
            summary_path = evidence_dir / 'summary.json'
            summary = json.loads(summary_path.read_text()) if summary_path.exists() else {}
            summary['passed'] = False
            summary['cleanupError'] = str(cleanup_error)
            write('summary.json', summary)
            raise
PY

#!/bin/bash
# Real production lifecycle stress; never permitted on a personal desktop.
set -euo pipefail
ym_stress_source="$(cd "$(dirname "$0")" && pwd -P)"
source "$ym_stress_source/guard.sh"
ym_stress_app="${1:?missing product app}"
ym_stress_helpers="${2:?missing helper directory}"
ym_stress_evidence="${3:?missing evidence directory}"
mkdir -p "$ym_stress_evidence"
python3 - "$ym_stress_app" "$ym_stress_helpers" "$ym_stress_evidence" "$ym_stress_source" <<'PY'
import json, os, pathlib, signal, subprocess, sys, time, traceback

assert os.environ.get('GITHUB_ACTIONS') == 'true'
assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
assert sys.platform == 'darwin'
app, helpers, evidence, source = map(pathlib.Path, sys.argv[1:])
started = time.monotonic()
deadline = started + 150
product_pid = None
companion = None
panel_id = None
records, failures = [], []
current_step = 'setup'

def write(name, obj):
    (evidence / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n')

def call(args, label, check=True, timeout=12):
    remaining = deadline-time.monotonic()
    if remaining <= 0:
        raise TimeoutError('150-second suite bound reached')
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True,
                            timeout=min(timeout, remaining))
    (evidence / (label+'.stdout')).write_text(result.stdout)
    (evidence / (label+'.stderr')).write_text(result.stderr)
    if check and result.returncode:
        raise RuntimeError(f'{label}: helper exit {result.returncode}')
    return result

def sample(label, screenshot=False):
    value = json.loads(call([helpers/'observe'], label+'-observe').stdout)
    write(label+'.json', value)
    if screenshot:
        call(['/usr/sbin/screencapture', '-x', evidence/(label+'.png')], label+'-capture')
    return value

def product(value):
    found = [a for a in value.get('applications', []) if a.get('bundleIdentifier') == 'dev.chekusu.yomado']
    assert len(found) == 1 and found[0]['pid'] == product_pid, 'owned product PID changed'
    assert not found[0].get('terminated'), 'owned product terminated'
    return found[0]

def panels(value):
    return [w for w in product(value).get('cgWindows', [])
            if w.get('kCGWindowName') == 'yomado' and w.get('kCGWindowIsOnscreen')]

def ax_panels(value):
    return [w for w in product(value).get('axWindows', [])
            if w.get('AXRole') == 'AXWindow' and w.get('AXTitle') == 'yomado']

def note(name, passed, detail=None):
    result = {'name':name, 'passed':bool(passed), 'detail':detail}
    records.append(result)
    if not passed:
        failures.append(result)
    print(json.dumps(result), flush=True)

def wait_open(label, require_focus=True):
    last = None
    for attempt in range(8):
        last = sample(f'{label}-wait-{attempt:02d}')
        owned = product(last)
        visible = panels(last)
        ax = ax_panels(last)
        if (owned.get('activationPolicy') == 0 and len(visible) == 1
            and (not require_focus or (owned.get('active') and len(ax) == 1
                 and ax[0].get('AXMain') and ax[0].get('AXFocused')))):
            break
        time.sleep(.25)
    value = sample(label, screenshot=True)
    owned = product(value)
    visible, ax = panels(value), ax_panels(value)
    note(label+' regular visible same panel', owned.get('activationPolicy') == 0
         and len(visible) == 1 and (panel_id is None or visible[0].get('kCGWindowNumber') == panel_id))
    if require_focus:
        note(label+' active and exact AX panel focus', owned.get('active') and len(ax) == 1
             and ax[0].get('AXMain') and ax[0].get('AXFocused'))
    if not visible:
        raise AssertionError('no visible panel to continue owned lifecycle test')
    return value

def menu_open(label):
    call([helpers/'panel-menu-actions', product_pid, 'open'], label+'-menu-open')
    time.sleep(.25)
    call([helpers/'panel-menu-actions', product_pid, 'select-open-panel'], label+'-menu-select')
    time.sleep(.35)
    return wait_open(label)

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for child in obj.values(): yield from walk(child)
    elif isinstance(obj, list):
        for child in obj: yield from walk(child)

try:
    for bundle in ['dev.chekusu.yomado', 'org.yomado.qa.Companion']:
        assert call([helpers/'observe', 'pid', bundle], 'preexisting-'+bundle,
                    check=False).returncode != 0, 'preexisting product/fixture cannot be owned'
    call([helpers/'stage-manager-action', 'off'], 'stage-manager-off')
    ui = json.loads(call([helpers/'observe', 'system-ui'], 'stage-manager-ui').stdout)
    write('stage-manager-ui.json', ui)
    toggles = [x for x in walk(ui) if x.get('AXDescription') == 'Stage Manager'
               and x.get('AXRole') == 'AXCheckBox']
    assert toggles and all(x.get('AXValue') == 0 for x in toggles), 'Stage Manager off not actually observed'
    call(['/usr/bin/osascript', '-e', 'tell application "System Events" to key code 53'], 'dismiss-control-center')
    fixture_control = evidence/'companion-control'
    fixture_control.mkdir(exist_ok=True)
    fixture_env = os.environ.copy()
    fixture_env['YM_QA_CONTROL_DIRECTORY'] = str(fixture_control)
    companion = subprocess.Popen([str(helpers/'Companion.app/Contents/MacOS/Companion')],
        env=fixture_env, stdout=(evidence/'companion.stdout').open('w'),
        stderr=(evidence/'companion.stderr').open('w'))
    time.sleep(.5)
    call(['/usr/bin/open', '-n', '--stdout', evidence/'product.stdout',
          '--stderr', evidence/'product.stderr', app], 'launch-product')
    for attempt in range(20):
        found = call([helpers/'observe', 'pid', 'dev.chekusu.yomado'], f'find-product-{attempt:02d}', check=False)
        if found.returncode == 0:
            product_pid = int(found.stdout.strip()); break
        time.sleep(.1)
    assert product_pid is not None, 'no owned product PID'
    initial = wait_open('initial', require_focus=False)
    panel_id = panels(initial)[0]['kCGWindowNumber']
    write('ownership.json', {'productPID':product_pid,'companionPID':companion.pid,'panelWindowID':panel_id})
    for cycle in range(1,11):
        prefix = f'cycle-{cycle:02d}'
        current_step = prefix+' minimize'
        call([helpers/'panel-window-actions', product_pid, 'minimize'], prefix+'-minimize')
        for attempt in range(6):
            pending = sample(prefix+f'-minimize-wait-{attempt:02d}')
            if any(w.get('AXMinimized') is True for w in ax_panels(pending)):
                break
            time.sleep(.2)
        minimized = sample(prefix+'-minimized', screenshot=True)
        note(prefix+' actually minimized', any(w.get('AXMinimized') is True for w in ax_panels(minimized)))
        current_step = prefix+' restore'
        menu_open(prefix+'-restored')
        current_step = prefix+' close'
        call(['/bin/bash', source/'close-owned-panel.sh', helpers, product_pid], prefix+'-close')
        # No input is sent during this fixed quiet interval. All observations
        # are independent readonly AX/CG/Dock samples; polling never calls the
        # product presenter and cannot repair its activation policy.
        quiet_start = time.monotonic()
        quiet = []
        while time.monotonic()-quiet_start < 3:
            value = sample(prefix+f'-quiet-{len(quiet):02d}')
            quiet.append(value)
            time.sleep(.35)
        final = sample(prefix+'-closed-final', screenshot=True)
        owned = product(final)
        dock = final.get('dock', {})
        note(prefix+' close becomes Accessory without further input', owned.get('activationPolicy') == 1,
             {'policy':owned.get('activationPolicy'),'quietSeconds':time.monotonic()-quiet_start})
        note(prefix+' close hides same panel', not panels(final))
        note(prefix+' Dock absent with readable positive control', dock.get('dockReadable')
             and dock.get('walkComplete') and dock.get('regularCompanionPositiveControl')
             and dock.get('yomadoIconObservation') == 'absent-in-readable-sample', dock)
        write(prefix+'-quiet-interval.json', {'seconds':time.monotonic()-quiet_start,
              'sampleCount':len(quiet),'inputSentDuringInterval':False})
        current_step = prefix+' reopen'
        menu_open(prefix+'-reopened')
    current_step = 'complete'
except Exception as error:
    failures.append({'name':current_step,'passed':False,'error':str(error),'traceback':traceback.format_exc()})
    try: sample('failure-state', screenshot=True)
    except Exception as capture_error:
        failures.append({'name':'failure evidence capture','error':str(capture_error)})
finally:
    write('summary.json', {'completed':current_step == 'complete','requestedCycles':10,
          'elapsedSeconds':time.monotonic()-started,'currentStep':current_step,
          'checks':records,'failures':failures,'passed':current_step == 'complete' and not failures,
          'scope':'Disposable hosted guest only; actual product launch stderr retained; no virtual-display persistence claim.'})
    # Only the exact processes started by this script are stopped.
    if product_pid is not None:
        try: os.kill(product_pid,signal.SIGTERM)
        except ProcessLookupError: pass
    if companion is not None and companion.poll() is None:
        companion.terminate()
    for _ in range(50):
        alive=False
        if product_pid is not None:
            try: os.kill(product_pid,0); alive=True
            except ProcessLookupError: pass
        if companion is not None and companion.poll() is None: alive=True
        if not alive: break
        time.sleep(.1)
    if alive:
        failures.append({'name':'owned process cleanup did not finish','passed':False})
        write('cleanup-failure.json',failures[-1])
sys.exit(1 if failures else 0)
PY

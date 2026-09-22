"""Import and run the migration's integration suite; fail on any Godot script error."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(command, log):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    output = result.stdout.decode('utf-8', errors='replace')
    log.write_text(output, encoding='utf-8')
    errors = [line for line in output.splitlines() if 'SCRIPT ERROR:' in line or line.startswith('ERROR:')]
    print(f'{log.name}: exit={result.returncode}, errors={len(errors)}')
    for line in errors[:30]:
        print(line)
    return result.returncode == 0 and not errors, output


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default='godot')
    parser.add_argument('--logs', default=str(ROOT / '.cache' / 'godot-verification'))
    args = parser.parse_args()
    logs = Path(args.logs)
    logs.mkdir(parents=True, exist_ok=True)
    base = [args.godot, '--headless', '--path', str(ROOT / 'godot')]
    imported, _ = run(base + ['--editor', '--import'], logs / 'import.log')
    if not imported:
        return 1
    tested, output = run(base + ['--script', 'res://tests/integration.gd'], logs / 'integration.log')
    line = next((line for line in output.splitlines() if line.startswith('HERON_INTEGRATION ')), '')
    if not line:
        print('No integration completion report was produced.')
        return 1
    report = json.loads(line.removeprefix('HERON_INTEGRATION '))
    report['engine_exit_and_log_passed'] = tested
    (ROOT / 'godot' / 'tests' / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f"Checks={len(report['checks'])}, failed={len(report['failures'])}")
    for failure in report['failures']:
        print('FAIL:', failure)
    jump_tested, jump_output = run(base + ['--script', 'res://tests/jump_regression.gd'], logs / 'jump.log')
    jump_line = next((line for line in jump_output.splitlines() if line.startswith('HERON_JUMP_REGRESSION ')), '')
    if not jump_line:
        print('No jump regression completion report was produced.')
        return 1
    jump_report = json.loads(jump_line.removeprefix('HERON_JUMP_REGRESSION '))
    print(f"Jump checks={len(jump_report['checks'])}, failed={len(jump_report['failures'])}")
    for failure in jump_report['failures']:
        print('FAIL:', failure)
    checkpoint_tested, checkpoint_output = run(base + ['--script', 'res://tests/checkpoint_regression.gd'], logs / 'checkpoint.log')
    checkpoint_line = next((line for line in checkpoint_output.splitlines() if line.startswith('HERON_CHECKPOINT_REGRESSION ')), '')
    if not checkpoint_line:
        print('No checkpoint regression completion report was produced.')
        return 1
    checkpoint_report = json.loads(checkpoint_line.removeprefix('HERON_CHECKPOINT_REGRESSION '))
    print(f"Checkpoint checks={len(checkpoint_report['checks'])}, failed={len(checkpoint_report['failures'])}")
    for failure in checkpoint_report['failures']:
        print('FAIL:', failure)
    debug_tested, debug_output = run(base + ['--script', 'res://tests/debug_menu_regression.gd'], logs / 'debug-menu.log')
    debug_line = next((line for line in debug_output.splitlines() if line.startswith('HERON_DEBUG_MENU_REGRESSION ')), '')
    if not debug_line:
        print('No debug menu regression completion report was produced.')
        return 1
    debug_report = json.loads(debug_line.removeprefix('HERON_DEBUG_MENU_REGRESSION '))
    print(f"Debug menu checks={len(debug_report['checks'])}, failed={len(debug_report['failures'])}")
    for failure in debug_report['failures']:
        print('FAIL:', failure)
    return 0 if tested and report['passed'] and jump_tested and jump_report['passed'] and checkpoint_tested and checkpoint_report['passed'] and debug_tested and debug_report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

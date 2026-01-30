#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / '.env'
IOS_DEBUG = ROOT / 'ios/Flutter/Debug.xcconfig'
IOS_RELEASE = ROOT / 'ios/Flutter/Release.xcconfig'

KEYS = [
    'GOOGLE_IOS_CLIENT_ID',
    'GOOGLE_REVERSED_CLIENT_ID',
    'GOOGLE_WEB_CLIENT_ID',
]


def parse_env(path: Path) -> dict:
    data = {}
    if not path.exists():
        raise FileNotFoundError(f'.env not found at {path}')
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def update_xcconfig(path: Path, values: dict) -> None:
    lines = []
    if path.exists():
        lines = path.read_text().splitlines()
    new_lines = [line for line in lines if not any(line.startswith(k + '=') for k in values.keys())]
    for key, value in values.items():
        if value:
            new_lines.append(f'{key}={value}')
    path.write_text('\n'.join(new_lines) + '\n')


def main() -> None:
    env = parse_env(ENV_PATH)
    missing = [k for k in KEYS if not env.get(k)]
    if missing:
        print('Missing values in .env:', ', '.join(missing))
    ios_values = {
        'GOOGLE_IOS_CLIENT_ID': env.get('GOOGLE_IOS_CLIENT_ID', ''),
        'GOOGLE_REVERSED_CLIENT_ID': env.get('GOOGLE_REVERSED_CLIENT_ID', ''),
    }
    update_xcconfig(IOS_DEBUG, ios_values)
    update_xcconfig(IOS_RELEASE, ios_values)

    web_id = env.get('GOOGLE_WEB_CLIENT_ID', '')
    if web_id:
        print('Web run command:')
        print(
            'flutter run -d web-server --web-port 5201 --web-hostname 127.0.0.1 '
            f"--dart-define=GOOGLE_WEB_CLIENT_ID={web_id}"
        )
    else:
        print('Set GOOGLE_WEB_CLIENT_ID in .env for web login.')


if __name__ == '__main__':
    main()

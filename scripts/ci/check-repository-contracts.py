#!/usr/bin/env python3
"""Focused repository invariants; package tests remain the compiler authority."""
from pathlib import Path
import plistlib
import re
import sys
import yaml

root = Path(__file__).resolve().parents[2]
errors = []

def require(condition, message):
    if not condition:
        errors.append(message)

def read(path):
    file = root / path
    require(file.is_file(), f'missing documented path: {path}')
    return file.read_text() if file.is_file() else ''

for path in ('docs/architecture.md', 'docs/development.md', 'docs/release.md',
             'docs/manual-tests/macos-checklist.md', 'site/README.md',
             'scripts/dev/verify.sh', 'Apps/macOS/project.yml'):
    read(path)

# Check explicit package target dependency declarations; swift package tests additionally
# compile these on macOS and the Linux CI job checks portability.
manifest = read('Packages/CalendarConnectors/Package.swift')
for line in (
    '.target(name: "CalendarCore")',
    '.target(name: "CalendarOAuth", dependencies: ["CalendarCore"])',
    '.target(name: "GoogleCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])',
    '.target(name: "MicrosoftCalendar", dependencies: ["CalendarCore", "CalendarOAuth"])',
):
    require(line in manifest, f'connector manifest dependency changed: {line}')
for package in ('CalendarConnectors', 'TimeTugCore'):
    for file in (root / 'Packages' / package / 'Sources').rglob('*.swift'):
        if package == 'CalendarConnectors' and file.parts[-2] not in ('CalendarCore', 'CalendarOAuth', 'GoogleCalendar', 'MicrosoftCalendar', 'CalendarTestSupport'):
            continue
        for match in re.finditer(r'^\s*import\s+(\w+)', file.read_text(), re.M):
            forbidden = {'AppKit', 'SwiftUI', 'EventKit', 'WidgetKit', 'FoundationModels'}
            require(match.group(1) not in forbidden, f'Apple/UI import in portable source: {file.relative_to(root)}')

registry = read('Apps/macOS/Sources/AppConnectors.swift')
for kind in ('EventKitConnectorKind', 'GoogleConnectorKind', 'MicrosoftConnectorKind'):
    require(f'registry.register({kind}' in registry, f'provider not registered: {kind}')
scopes = read('Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftConnectorKind.swift')
# Microsoft sign-in is read-only (ADR 0017): the app never writes events. Widening it is a deliberate change to this check.
for scope in ('Calendars.Read', 'Calendars.Read.Shared', 'MailboxSettings.Read'):
    require(f'"{scope}"' in scopes, f'intended Microsoft scope absent: {scope}')
for scope in ('Calendars.ReadWrite', 'Calendars.ReadWrite.Shared'):
    require(f'"{scope}"' not in scopes, f'Microsoft scope must stay read-only (ADR 0017): {scope}')
source = read('Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftCalendarSource.swift')
require('canWrite: true' in source and 'canEditAttendees: true' in source,
        'Microsoft write capabilities changed')
require('extension MicrosoftCalendarSource: WritableCalendarSource' in read('Packages/CalendarConnectors/Sources/MicrosoftCalendar/MicrosoftCalendarSource+Write.swift'),
        'Microsoft write protocol implementation absent')
for provider, path in (
    ('GoogleCalendarSource', 'Packages/CalendarConnectors/Sources/GoogleCalendar'),
    ('EventKitSource', 'Packages/EventKitSource/Sources/EventKitSource'),
):
    require('canWrite: true' in read(f'{path}/{provider}.swift'),
            f'{provider} write capability changed')
    require(f'extension {provider}: WritableCalendarSource' in read(f'{path}/{provider}+Write.swift'),
            f'{provider} write protocol implementation absent')

# XcodeGen is the source of truth for generated plist properties.
project = yaml.safe_load(read('Apps/macOS/project.yml'))
for target, path in (('TimeTug', 'Apps/macOS/Sources/Info.plist'),
                     ('TimeTugWidgets', 'Apps/macOS/Widgets/Info.plist')):
    props = project['targets'][target]['info']['properties']
    with (root / path).open('rb') as stream:
        plist = plistlib.load(stream)
    for key, value in props.items():
        require(plist.get(key) == value, f'{path} differs from project.yml: {key}')

if errors:
    for error in errors:
        print(f'FAIL: {error}', file=sys.stderr)
    sys.exit(1)
print('PASS: repository contracts')

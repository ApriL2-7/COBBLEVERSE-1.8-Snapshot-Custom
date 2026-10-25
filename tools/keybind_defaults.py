"""Shared, collision-free player key defaults for the integrated RC."""
from collections import defaultdict

UNKNOWN = 'key.keyboard.unknown'
DISABLE = {
    'key_key.super_resolution.open_config',
    'key_iris.keybind.toggleShaders',
    'key_keybind.sophisticatedbackpacks.sort',
    'key_keybind.sophisticatedstorage.sort',
}

def clean_options(text):
    lines = text.splitlines()
    bindings = dict(line.split(':', 1) for line in lines if line.startswith('key_') and ':' in line)
    original = bindings.copy()
    bindings['key_key.ftbquests.quests'] = 'key.keyboard.grave.accent'
    bindings['key_key.ftbquests.gui.recenter'] = 'key.keyboard.home'
    for action in DISABLE:
        if action in bindings:
            bindings[action] = UNKNOWN
    # Prefer normal gameplay bindings over shortcuts inside the quest GUI.
    groups = defaultdict(list)
    for action, key in bindings.items():
        if key != UNKNOWN:
            groups[key].append(action)
    for key, actions in groups.items():
        if len(actions) < 2:
            continue
        gameplay = [a for a in actions if not a.startswith('key_key.ftbquests.gui')]
        if len(gameplay) > 1:
            raise RuntimeError(f'Unresolved gameplay conflict: {key}: {gameplay}')
        keep = gameplay[0] if gameplay else actions[0]
        for action in actions:
            if action != keep:
                bindings[action] = UNKNOWN
    changes = [{'action': a, 'before': original.get(a), 'after': k}
               for a, k in bindings.items() if original.get(a) != k]
    result = []
    seen = set()
    for line in lines:
        action = line.split(':', 1)[0]
        if action in bindings:
            if action in seen:
                continue
            seen.add(action)
            line = action + ':' + bindings[action]
        result.append(line)
    result.extend(a + ':' + k for a, k in bindings.items() if a not in seen)
    return '\n'.join(result) + '\n', changes

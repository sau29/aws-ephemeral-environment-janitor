from pathlib import Path
import json

path = Path('terraform/tfplan.json')
if not path.exists():
    print('ERROR: terraform/tfplan.json not found')
    raise SystemExit(2)
raw = path.read_bytes()
encodings = ['utf-8-sig','utf-8','utf-16','utf-16-le','utf-16-be']
text = None
for e in encodings:
    try:
        text = raw.decode(e)
        print(f'DECODE_OK: {e}')
        break
    except Exception as exc:
        # try next
        pass
if text is None:
    # last resort: latin1
    try:
        text = raw.decode('latin-1')
        print('DECODE_OK: latin-1 (fallback)')
    except Exception as exc:
        print('ERROR: could not decode tfplan.json')
        raise SystemExit(3)

plan = json.loads(text)
found = []
# Check planned_values root_module resources
for r in plan.get('planned_values', {}).get('root_module', {}).get('resources', []):
    if r.get('type') == 'aws_subnet':
        vals = r.get('values', {})
        sid = vals.get('id')
        if sid:
            found.append(('planned_values', sid))
        else:
            # show cidr and note
            cidr = vals.get('cidr_block')
            found.append(('planned_values_cidr', cidr))
# Check resource_changes for any concrete IDs in after/before
for rc in plan.get('resource_changes', []):
    if rc.get('type') == 'aws_subnet':
        change = rc.get('change', {})
        after = change.get('after', {})
        if isinstance(after, dict):
            if after.get('id'):
                found.append(('resource_changes_after', after.get('id')))
            # sometimes subnet_id appears
            if after.get('subnet_id'):
                found.append(('resource_changes_after_subnet_id', after.get('subnet_id')))
        # also check after_unknown for id presence (but true/false)
        after_unknown = change.get('after_unknown', {})
        if after_unknown.get('id') is True:
            found.append(('resource_changes_after_unknown_id', '<will be created>'))

if not found:
    print('No concrete subnet id found in tfplan.json. Resource is planned to be created or id is unavailable.')
else:
    for kind, val in found:
        print(kind + ':', val)

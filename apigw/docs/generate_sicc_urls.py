import zipfile, xml.etree.ElementTree as ET, re, json

with zipfile.ZipFile(r'c:\Projects\cde\apigw\docs\VA_ForWebhookCreation.xlsx') as z:
    sst_root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    strings = [''.join(t.text for t in si.iter('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t') if t.text) for si in sst_root.findall('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}si')]
    sheet_root = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
    ns = {'ns': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    rows = []
    for row in sheet_root.findall('.//ns:row', ns):
        cells = {}
        for c in row.findall('ns:c', ns):
            ref = c.get('r')
            t = c.get('t')
            v = c.find('ns:v', ns)
            val = v.text if v is not None else ''
            if t == 's' and val:
                val = strings[int(val)]
            col = ''.join([ch for ch in ref if ch.isalpha()])
            cells[col] = val
        if cells.get('A') and cells.get('A') != '#':
            rows.append(cells)

entries = []

# Entry 1 (Crowding)
entries.append({
    'num': 1,
    'route_path': '/va/sov-38alt-l4-icc-1-crowding',
    'webhook': 'crowding_sov_38alt_l4_icc_1',
    'deviceName': 'SOV 38ALT L4 ICC 1 VA CROWDING',
    'incidentType': 'CROWDING',
    'associatedCamera': 'SOV 38ALT L4 ICC 1'
})

# Entry 2 (Loitering)
entries.append({
    'num': 2,
    'route_path': '/va/sov-38alt-l4-lift-lobby-loitering',
    'webhook': 'loitering_sov_38alt_l4_lift_lobby',
    'deviceName': 'SOV 38ALT L4 LIFT LOBBY VA LOITERING',
    'incidentType': 'LOITERING',
    'associatedCamera': 'SOV 38ALT L4 Lift Lobby'
})

for r in rows[2:]: # items 3 to 21
    idx = int(r['A'])
    inc = r['K'].strip().upper()
    inc_type = 'ILLEGAL_PARKING' if inc == 'ILLEGAL PARKING' else inc
    inc_slug = 'illegal-parking' if inc == 'ILLEGAL PARKING' else inc.lower()
    inc_webhook_slug = 'illegal_parking' if inc == 'ILLEGAL PARKING' else inc.lower()
    
    asset_id = r['D'].strip()
    # Route slug with hyphens
    clean_asset_route = re.sub(r'[^a-zA-Z0-9]+', '-', asset_id.lower()).strip('-')
    route_path = f"/va/{clean_asset_route}-{inc_slug}"
    
    # Webhook slug with underscores
    clean_asset_wh = re.sub(r'[^a-zA-Z0-9]+', '_', asset_id.lower()).strip('_')
    webhook = f"{inc_webhook_slug}_{clean_asset_wh}"
    
    cam = r['C'].strip()
    if cam == 'SOV 38ALT Side Fencing Fencing':
        cam = 'SOV 38ALT Side Fencing'
    elif cam == 'SOV 38ALT L6 Lift Lift Lobby':
        cam = 'SOV 38ALT L6 Lift Lobby'
    elif cam == 'SOV 38ALT Main Gate Perimiter':
        cam = 'SOV 38ALT Main Gate Perimeter'
        
    device_name = r['J'].strip()
    
    entries.append({
        'num': idx,
        'route_path': route_path,
        'webhook': webhook,
        'deviceName': device_name,
        'incidentType': inc_type,
        'associatedCamera': cam
    })

header = """# Credential
vizzio@imops.local
xAJHkkm7m3V5MhtF0xGM

BACKEND_API = http://10.65.51.252:8088
"""

blocks = [header.strip()]

for e in entries:
    block = f"""# {e['num']}. GET/POST {e['route_path']}

upstream:
(POST {{{{BACKEND_API}}}}/api/incidents/monitor):

{{
  "site": "SOV 38ALT",
  "deviceName": "{e['deviceName']}",
  "incidentType": "{e['incidentType']}",
  "mode": "incident",
  "metadata": {{
    "source": "vizzio_va",
    "webhook": "{e['webhook']}",
    "associatedCamera": "{e['associatedCamera']}"
  }}
}}"""
    blocks.append(block)

full_output = "\n\n\n\n".join(blocks) + "\n"

with open(r'c:\Projects\cde\apigw\docs\VA_SICC_URLs', 'w', encoding='utf-8') as f:
    f.write(full_output)

print("Updated VA_SICC_URLs successfully. Total entries:", len(entries))

/**
 * n8n Code node: poll Proscalar TPI and build access-snapshot payload for iMOPS.
 * Env on n8n-server: PROSCALAR_TPI_BASE_URL, PROSCALAR_TPI_ACCOUNT_ID, PROSCALAR_TPI_CLIENT_SECRET,
 * PROSCALAR_TPI_INSECURE_TLS (default true).
 */
const REQUEST_GAP_MS = 600;

const baseUrl = String($env.PROSCALAR_TPI_BASE_URL || '').replace(/\/$/, '');
const accountId = $env.PROSCALAR_TPI_ACCOUNT_ID;
const clientSecret = $env.PROSCALAR_TPI_CLIENT_SECRET;
const insecure = String($env.PROSCALAR_TPI_INSECURE_TLS || 'true').toLowerCase() !== 'false';

if (!baseUrl || !accountId || !clientSecret) {
  throw new Error('Configure PROSCALAR_TPI_BASE_URL, PROSCALAR_TPI_ACCOUNT_ID, PROSCALAR_TPI_CLIENT_SECRET on n8n');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function pageOf(data) {
  const page = data?.results && typeof data.results === 'object' && !Array.isArray(data.results)
    ? data.results
    : data;
  const list = Array.isArray(page?.list) ? page.list : (Array.isArray(page) ? page : []);
  const totalItem = Number(page?.totalItem);
  return {
    list,
    totalItem: Number.isFinite(totalItem) ? totalItem : list.length,
    totalPage: Number(page?.totalPage || 1),
  };
}

function classifyDoor(door) {
  const rawDoor = String(door?.doorStatus ?? '').trim().toLowerCase();
  const rawLock = String(door?.lockStatus ?? '').trim().toLowerCase();
  if (rawDoor === 'forced opened' || rawDoor === '5002' || rawDoor.includes('forced')) return 'forceOpen';
  if (rawDoor === 'left opened' || rawDoor === '5001' || rawDoor.includes('left open') || rawDoor.includes('held open')) return 'heldOpen';
  if (rawDoor === 'opened' || rawDoor === '5000' || rawDoor === 'open') return 'open';
  const isClosed = rawDoor === 'closed' || rawDoor === '5003';
  const isUnlocked = rawLock === 'activated' || rawLock === '5018' || rawLock === 'unlocked';
  if (isClosed && isUnlocked) return 'unlocked';
  if (isClosed) return 'locked';
  return 'unknown';
}

let token = null;
let tokenAt = 0;

async function httpRequest(opts) {
  return this.helpers.httpRequest({
    skipSslCertificateValidation: insecure,
    json: true,
    ...opts,
  });
}

async function getToken() {
  const ttl = 3 * 60 * 60 * 1000;
  if (token && (Date.now() - tokenAt) < ttl - 60_000) return token;
  const res = await httpRequest.call(this, {
    method: 'POST',
    url: `${baseUrl}/idp/1.0/service-accounts/login`,
    body: { accountId, clientSecret },
    headers: { 'Content-Type': 'application/json' },
  });
  token = res?.token || res?.data?.token;
  if (!token) throw new Error('Proscalar login did not return a token');
  tokenAt = Date.now();
  return token;
}

async function tpiGet(path, params = {}, retried = false) {
  const tok = await getToken.call(this);
  try {
    const data = await httpRequest.call(this, {
      method: 'GET',
      url: `${baseUrl}${path}`,
      qs: params,
      headers: { Authorization: `Proscalar-tpi ${tok}` },
    });
    return data?.list ? data : (data?.data || data);
  } catch (err) {
    const status = err?.statusCode || err?.response?.statusCode || err?.httpCode;
    if (status === 401 && !retried) {
      token = null;
      return tpiGet.call(this, path, params, true);
    }
    const message = err?.message || String(err);
    throw new Error(`Proscalar GET ${path} failed: ${message}`);
  }
}

async function listAllDoors() {
  const doors = [];
  let page = 0;
  let totalPage = 1;
  while (page < totalPage) {
    const data = await tpiGet.call(this, '/event/hardware/door/list', { page, size: 100, view: 'detail' });
    const list = Array.isArray(data?.list) ? data.list : (Array.isArray(data) ? data : []);
    doors.push(...list);
    totalPage = Number(data?.totalPage || 1);
    page += 1;
    if (page < totalPage) await sleep(REQUEST_GAP_MS);
  }
  return doors;
}

async function pollPanicAndAlarmGroups() {
  const data = await tpiGet.call(this, '/central/1.0/alarm-groups', { size: 100 });
  const groups = pageOf(data).list;
  const panicZones = [];
  const fireZones = [];
  const panicInputIdSet = new Set();

  for (const group of groups) {
    const zones = Array.isArray(group?.alarmZones)
      ? group.alarmZones
      : (Array.isArray(group?.zones)
        ? group.zones
        : (Array.isArray(group?.accessZones) ? group.accessZones : []));

    for (const zone of zones) {
      const zoneType = String(zone?.setting?.zoneType || zone?.zoneType || zone?.type || '').toUpperCase();
      const inputIds = Array.isArray(zone?.setting?.logicalInputIds)
        ? zone.setting.logicalInputIds
        : (Array.isArray(zone?.logicalInputIds) ? zone.logicalInputIds : []);

      const summary = {
        alarmGroupId: group?.id || group?.alarmGroupId || null,
        alarmGroupName: group?.name || null,
        zoneId: zone?.zoneId || zone?.id || zone?.alarmZoneId || null,
        zoneName: zone?.zoneName || zone?.name || 'Unnamed Zone',
        zoneType,
        alarmRaised: Boolean(zone?.alarmRaised),
        lastAlarmRaisedTs: zone?.lastAlarmRaisedTs || null,
        lastAlarmNormalTs: zone?.lastAlarmNormalTs || null,
        logicalInputIds: inputIds,
      };

      if (zoneType === 'PANIC') {
        panicZones.push(summary);
        for (const id of inputIds) {
          if (id) panicInputIdSet.add(String(id));
        }
      } else if (zoneType === 'FIRE') {
        fireZones.push(summary);
      }
    }
  }

  const panicInputs = [];
  const panicInputIds = Array.from(panicInputIdSet);
  if (panicInputIds.length > 0) {
    await sleep(REQUEST_GAP_MS);
    const inputData = await tpiGet.call(this, '/event/hardware/logical-input/list', {
      ids: panicInputIds.join(','),
      size: Math.max(50, panicInputIds.length),
    });
    for (const inp of pageOf(inputData).list) {
      const state = String(inp?.state || inp?.status || 'Unknown').trim();
      panicInputs.push({
        id: inp?.id || inp?.logicalInputId || null,
        name: inp?.name || inp?.logicalInputName || null,
        state,
        isActive: ['active', 'open', 'tamper'].includes(state.toLowerCase()),
      });
    }
  }

  return {
    latchedCount: panicZones.filter((z) => z.alarmRaised).length,
    activeInputCount: panicInputs.filter((i) => i.isActive).length,
    fireLatchedCount: fireZones.filter((z) => z.alarmRaised).length,
    zones: panicZones,
    inputs: panicInputs,
    polledAt: new Date().toISOString(),
  };
}

async function pollUnprocessedEmergencyAlarms() {
  const data = await tpiGet.call(this, '/event/alarm/list', { eventCodes: '5014', size: 100 });
  const page = pageOf(data);
  return {
    unprocessedCount: page.totalItem,
    alarms: page.list.slice(0, 25).map((item) => ({
      id: item?.id || null,
      eventCode: String(item?.eventCode || '5014'),
      eventPointId: item?.eventPointId || null,
      eventPointName: item?.eventPointName || null,
      eventSourceId: item?.eventSourceId || null,
      eventSourceName: item?.eventSourceName || null,
      eventTimestamp: item?.eventTimestamp || null,
    })),
    polledAt: new Date().toISOString(),
  };
}

const doors = await listAllDoors.call(this);
const access = { locked: 0, open: 0, forceOpen: 0, heldOpen: 0, unlocked: 0, unknown: 0 };
for (const door of doors) {
  access[classifyDoor(door)] += 1;
}

let panic = null;
try {
  await sleep(REQUEST_GAP_MS);
  panic = await pollPanicAndAlarmGroups.call(this);
} catch (e) {
  panic = null;
}

let emergency = null;
try {
  await sleep(REQUEST_GAP_MS);
  emergency = await pollUnprocessedEmergencyAlarms.call(this);
} catch (e) {
  emergency = null;
}

const polledAt = new Date().toISOString();

return [{
  json: {
    polledAt,
    total: doors.length,
    access,
    panic,
    emergency,
    metadata: {
      source: 'proscalar_n8n_door_poll',
      workflow: 'Proscalar Door Poll → iMOPS Access Snapshot',
    },
  },
}];

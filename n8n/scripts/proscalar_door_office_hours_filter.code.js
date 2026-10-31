/**
 * n8n Code node: TU door held/forced + close idle suppress Mon–Fri 09:00–17:00 Asia/Kuala_Lumpur.
 * Place after "Classify Event Code". Sets isScheduleFiltered on the item; downstream IF skips iMOPS POST.
 */
const item = $input.first().json || {};
const eventCode = String(item.eventCode ?? '');

/** Proscalar: held open, forced open, door closed (idle pair) */
const SUPPRESS_EVENT_CODES = new Set(['5001', '5002', '5003', '8000']);
const TIMEZONE = 'Asia/Kuala_Lumpur';
const START_MINUTES = 9 * 60;
const END_MINUTES = 17 * 60;

function weekdayAndMinutes(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TIMEZONE,
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  const pick = (type) => parts.find((p) => p.type === type)?.value;
  const weekday = pick('weekday');
  const dayMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
  const day = dayMap[weekday];
  if (day === undefined) return null;
  const minutes = Number(pick('hour')) * 60 + Number(pick('minute'));
  if (Number.isNaN(minutes)) return null;
  return { day, minutes };
}

function isOfficeSuppressWindow(iso) {
  const local = weekdayAndMinutes(iso);
  if (!local) return false;
  if (local.day < 1 || local.day > 5) return false;
  return local.minutes >= START_MINUTES && local.minutes <= END_MINUTES;
}

const eventTimestamp = item.eventTimestamp || new Date().toISOString();
const isScheduleFiltered =
  SUPPRESS_EVENT_CODES.has(eventCode) && isOfficeSuppressWindow(eventTimestamp);

return [
  {
    json: {
      ...item,
      isScheduleFiltered,
      scheduleFilterReason: isScheduleFiltered
        ? 'door_mon_fri_09_17_asia_kuala_lumpur'
        : null,
    },
  },
];

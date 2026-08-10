/**
 * UUIDv7 on the server, for the same reason as on the phone: 48 bits of
 * big-endian millisecond timestamp first, so ids sort by creation time and a
 * listing is an index scan rather than a sort. `crypto.randomUUID()` is v4 and
 * scatters, which is fine for a cache row and wrong for anything the log keeps.
 */
export function uuidV7(now = Date.now()): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const timestamp = BigInt(now);
  for (let index = 0; index < 6; index += 1) {
    bytes[index] = Number((timestamp >> BigInt(8 * (5 - index))) & 0xffn);
  }
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x70; // version 7
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80; // variant 10
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

const ROOM_CODE_REGEX = /^[A-Z0-9]{6}$/;

/**
 * Validates and normalizes a 6-character alphanumeric room code.
 * Returns the uppercase string if valid, or null if invalid.
 */
export function getValidatedRoomCode(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const upper = raw.toUpperCase().trim();
  return ROOM_CODE_REGEX.test(upper) ? upper : null;
}

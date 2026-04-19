/**
 * Client-side normalization for contact dedup keys.
 * These run before calling the `create_or_link_contact` / `find_contact_by_phone_or_email`
 * RPCs so that "same contact" actually collides on the DB's partial unique indexes.
 */

const PHONE_SEPARATORS = /[\s\-()\.]/g;
const E164 = /^\+[1-9]\d{6,14}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function normalizePhone(input: string | null | undefined): string | null {
  if (input == null) return null;
  const cleaned = input.replace(PHONE_SEPARATORS, "");
  if (cleaned === "") return null;
  return E164.test(cleaned) ? cleaned : null;
}

export function normalizeEmail(input: string | null | undefined): string | null {
  if (input == null) return null;
  const trimmed = input.trim().toLowerCase();
  if (trimmed === "") return null;
  return EMAIL.test(trimmed) ? trimmed : null;
}

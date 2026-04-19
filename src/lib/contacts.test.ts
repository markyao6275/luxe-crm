import { describe, expect, it } from "vitest";
import { normalizeEmail, normalizePhone } from "./contacts";

describe("normalizePhone", () => {
  it("strips whitespace, dashes, parens, and dots", () => {
    expect(normalizePhone("+1 (415) 555-0100")).toBe("+14155550100");
    expect(normalizePhone("+63.917.555.0100")).toBe("+639175550100");
  });

  it("returns null for nullish, empty, or invalid input", () => {
    expect(normalizePhone(null)).toBeNull();
    expect(normalizePhone(undefined)).toBeNull();
    expect(normalizePhone("")).toBeNull();
    expect(normalizePhone("   ")).toBeNull();
    expect(normalizePhone("415-555-0100")).toBeNull();   // missing +
    expect(normalizePhone("+0123456789")).toBeNull();    // leading 0
    expect(normalizePhone("+1abc4155550100")).toBeNull();
  });

  it("canonicalizes so equivalent inputs collide", () => {
    expect(normalizePhone("+1-415-555-0100")).toBe(normalizePhone("+1 (415) 555 0100"));
  });
});

describe("normalizeEmail", () => {
  it("lowercases and trims", () => {
    expect(normalizeEmail("  Alice@Example.COM  ")).toBe("alice@example.com");
  });

  it("returns null for nullish, empty, or invalid input", () => {
    expect(normalizeEmail(null)).toBeNull();
    expect(normalizeEmail(undefined)).toBeNull();
    expect(normalizeEmail("")).toBeNull();
    expect(normalizeEmail("   ")).toBeNull();
    expect(normalizeEmail("not-an-email")).toBeNull();
    expect(normalizeEmail("a@b")).toBeNull();
  });
});

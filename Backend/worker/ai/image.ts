import { HttpError } from "../lib/http-error";

const MAX_IMAGE_BYTES = 8_000_000;

export function decodeBase64Image(base64: string): Uint8Array {
  let binary: string;
  try {
    binary = atob(base64);
  } catch {
    throw new HttpError(400, "imageBase64 is not valid base64.");
  }
  if (binary.length > MAX_IMAGE_BYTES) {
    throw new HttpError(413, "Meal image exceeds the 8 MB request limit.");
  }
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function encodeBase64Image(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 32_768;
  for (let offset = 0; offset < bytes.byteLength; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

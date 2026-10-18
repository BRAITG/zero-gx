export function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Throws on input that is not base64url. */
export function fromBase64url(text: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(atob(text.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
}

/** An opaque id such as `p_` + 16 characters of [a-z0-9]. */
export function randomId(prefix: string, length: number): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  let id = prefix;
  while (id.length < prefix.length + length) {
    for (const byte of crypto.getRandomValues(new Uint8Array(length))) {
      // Bytes from 252 up would favour the first characters of the alphabet.
      if (byte < 252 && id.length < prefix.length + length) id += alphabet[byte % 36];
    }
  }
  return id;
}

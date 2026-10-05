// mojito.wells.ee/download → latest release DMG. 302 so it always
// resolves to the newest version at request time.
//
// Site pages link here with ?ref=<page>&at=<nav|cta> so downloads can be
// traced back to the guide that sent them. One structured log line per
// request lands in Workers Logs (observability is on in wrangler.jsonc); it
// carries the ref, the referring host and the country — no IP, no cookies.
const DMG = "https://github.com/wr/mojito/releases/latest/download/Mojito.dmg";

function refererHost(request) {
  try {
    return new URL(request.headers.get("Referer") || "").hostname;
  } catch {
    return "";
  }
}

export default {
  fetch(request) {
    const url = new URL(request.url);
    console.log(
      JSON.stringify({
        event: "download",
        ref: (url.searchParams.get("ref") || "").slice(0, 80),
        at: (url.searchParams.get("at") || "").slice(0, 20),
        referer: refererHost(request),
        country: request.cf?.country || "",
      }),
    );
    return Response.redirect(DMG, 302);
  },
};

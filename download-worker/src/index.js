// mojito.wells.ee/download → latest release DMG. 302 so it always
// resolves to the newest version at request time.
export default {
  fetch() {
    return Response.redirect(
      "https://github.com/wr/mojito/releases/latest/download/Mojito.dmg",
      302,
    );
  },
};

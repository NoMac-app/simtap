import assert from "node:assert/strict";
import { test } from "node:test";

import { localeParts, timeZoneName } from "../src/tools/app-control.ts";

test("a locale is split as iOS keeps it, and anything else is refused", () => {
  assert.deepEqual(localeParts("fr_FR"), { language: "fr-FR", locale: "fr_FR" });
  assert.deepEqual(localeParts("pt-BR"), { language: "pt-BR", locale: "pt_BR" });
  assert.deepEqual(localeParts("zh-Hans_CN"), { language: "zh-Hans-CN", locale: "zh-Hans_CN" });
  assert.deepEqual(localeParts("es-419"), { language: "es-419", locale: "es_419" });
  assert.deepEqual(localeParts("en"), { language: "en", locale: "en" });
  for (const bad of ["french", "FR_fr", "fr_FR; rm -rf", ""]) assert.throws(() => localeParts(bad), /is not a language and region/, bad);
});

test("a time zone is an IANA name this machine knows", () => {
  assert.equal(timeZoneName(" Europe/Paris "), "Europe/Paris");
  assert.equal(timeZoneName("America/Argentina/Buenos_Aires"), "America/Argentina/Buenos_Aires");
  assert.equal(timeZoneName("UTC"), "UTC");
  for (const bad of ["Mars/Base", "Europe/Paris; echo", "../../etc"]) assert.throws(() => timeZoneName(bad), /is not a time zone/, bad);
});

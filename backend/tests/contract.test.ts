import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import SwaggerParser from "@apidevtools/swagger-parser";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { project, type Journey } from "../src/domain.ts";
import { normalize } from "../src/normalize.ts";
test("OpenAPI parses and shared Swift/TypeScript fixtures conform to the documented wire contract", async () => {
  const url = new URL("../../contracts/openapi.json", import.meta.url);
  const spec = JSON.parse(readFileSync(url, "utf8"));
  await SwaggerParser.validate(url.pathname);
  const ajv = new Ajv2020({ strict: false });
  addFormats(ajv);
  const schema = (name: string) =>
    ajv.compile({
      components: spec.components,
      $ref: `#/components/schemas/${name}`,
    });
  const journey = JSON.parse(
    readFileSync(
      new URL("../../contracts/fixtures/demo-journey.json", import.meta.url),
      "utf8",
    ),
  );
  const validateJourney = schema("Journey");
  assert.ok(validateJourney(journey), JSON.stringify(validateJourney.errors));
  const validateState = schema("ActivityState");
  assert.ok(
    validateState(project(journey as Journey, 1794003840)),
    JSON.stringify(validateState.errors),
  );
  const trains = normalize(
    JSON.parse(
      readFileSync(
        new URL("../../contracts/fixtures/via-synthetic.json", import.meta.url),
        "utf8",
      ),
    ),
    "2026-10-31T02:00:00Z",
    1,
  );
  const validateTrain = schema("TrainSnapshot");
  for (const train of trains)
    assert.ok(validateTrain(train), JSON.stringify(validateTrain.errors));
});

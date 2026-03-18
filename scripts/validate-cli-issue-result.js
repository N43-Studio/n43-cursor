#!/usr/bin/env node

const fs = require("node:fs");

const args = process.argv.slice(2);

if (args.length !== 1) {
  console.error("usage: scripts/validate-cli-issue-result.js <result-json>");
  process.exit(2);
}

const [resultPath] = args;

let payload;

try {
  payload = JSON.parse(fs.readFileSync(resultPath, "utf8"));
} catch (error) {
  console.error(`invalid JSON: ${error.message}`);
  process.exit(1);
}

const errors = [];

const allowedTopLevelKeys = new Set([
  "contract_version",
  "issue_id",
  "iteration",
  "outcome",
  "exit_code",
  "failure_category",
  "retryable",
  "retry_after_seconds",
  "handoff_required",
  "handoff",
  "summary",
  "validation_results",
  "artifacts",
  "metrics",
]);

const allowedFailureCategories = new Set([
  "validation_failure",
  "implementation_error",
  "ambiguous_requirements",
  "transient_infrastructure",
  "tool_timeout",
  "tool_contract_violation",
  "unknown",
  null,
]);

const allowedValidationStates = new Set(["pass", "fail", "skipped"]);
const allowedExitCodes = new Set([0, 10, 11, 20, 30]);
const allowedOutcomes = new Set(["success", "failure", "human_required"]);

function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isInteger(value) {
  return Number.isInteger(value);
}

function expect(condition, message) {
  if (!condition) {
    errors.push(message);
  }
}

expect(isPlainObject(payload), "result payload must be an object");

if (!isPlainObject(payload)) {
  console.error(errors.join("\n"));
  process.exit(1);
}

for (const key of Object.keys(payload)) {
  expect(allowedTopLevelKeys.has(key), `unexpected top-level field: ${key}`);
}

for (const key of [
  "contract_version",
  "issue_id",
  "iteration",
  "outcome",
  "exit_code",
  "retryable",
  "handoff_required",
  "summary",
  "validation_results",
  "artifacts",
  "metrics",
]) {
  expect(Object.hasOwn(payload, key), `missing required field: ${key}`);
}

expect(payload.contract_version === "1.0", "contract_version must equal 1.0");
expect(typeof payload.issue_id === "string" && payload.issue_id.length > 0, "issue_id must be a non-empty string");
expect(isInteger(payload.iteration) && payload.iteration >= 1, "iteration must be an integer >= 1");
expect(allowedOutcomes.has(payload.outcome), "outcome must be success, failure, or human_required");
expect(allowedExitCodes.has(payload.exit_code), "exit_code must be one of 0, 10, 11, 20, 30");
expect(allowedFailureCategories.has(payload.failure_category), "failure_category must be an allowed value or null");
expect(typeof payload.retryable === "boolean", "retryable must be a boolean");

if (!Object.hasOwn(payload, "retry_after_seconds")) {
  // optional by schema
} else {
  expect(
    payload.retry_after_seconds === null || (isInteger(payload.retry_after_seconds) && payload.retry_after_seconds >= 0),
    "retry_after_seconds must be null or an integer >= 0",
  );
}

expect(typeof payload.handoff_required === "boolean", "handoff_required must be a boolean");
expect(typeof payload.summary === "string" && payload.summary.length > 0, "summary must be a non-empty string");

if (payload.handoff === null || payload.handoff === undefined) {
  if (payload.handoff_required) {
    errors.push("handoff must be populated when handoff_required=true");
  }
} else if (!isPlainObject(payload.handoff)) {
  errors.push("handoff must be an object or null");
} else {
  const allowedHandoffKeys = new Set([
    "assumptions_made",
    "questions_for_human",
    "impact_if_wrong",
    "proposed_revision_plan",
  ]);
  for (const key of Object.keys(payload.handoff)) {
    expect(allowedHandoffKeys.has(key), `unexpected handoff field: ${key}`);
  }
  for (const key of allowedHandoffKeys) {
    expect(Object.hasOwn(payload.handoff, key), `missing handoff field: ${key}`);
  }
  expect(Array.isArray(payload.handoff.assumptions_made), "handoff.assumptions_made must be an array");
  expect(Array.isArray(payload.handoff.questions_for_human), "handoff.questions_for_human must be an array");
  for (const [index, value] of (payload.handoff.assumptions_made || []).entries()) {
    expect(typeof value === "string" && value.length > 0, `handoff.assumptions_made[${index}] must be a non-empty string`);
  }
  for (const [index, value] of (payload.handoff.questions_for_human || []).entries()) {
    expect(typeof value === "string" && value.length > 0, `handoff.questions_for_human[${index}] must be a non-empty string`);
  }
  expect(
    typeof payload.handoff.impact_if_wrong === "string" && payload.handoff.impact_if_wrong.length > 0,
    "handoff.impact_if_wrong must be a non-empty string",
  );
  expect(
    typeof payload.handoff.proposed_revision_plan === "string" && payload.handoff.proposed_revision_plan.length > 0,
    "handoff.proposed_revision_plan must be a non-empty string",
  );
}

const validationResults = payload.validation_results;
const requiredValidationKeys = ["lint", "typecheck", "test", "build"];
if (!isPlainObject(validationResults)) {
  errors.push("validation_results must be an object");
} else {
  for (const key of Object.keys(validationResults)) {
    expect(requiredValidationKeys.includes(key), `unexpected validation_results field: ${key}`);
  }
  for (const key of requiredValidationKeys) {
    expect(Object.hasOwn(validationResults, key), `missing validation_results field: ${key}`);
    expect(allowedValidationStates.has(validationResults[key]), `validation_results.${key} must be pass, fail, or skipped`);
  }
}

const artifacts = payload.artifacts;
if (!isPlainObject(artifacts)) {
  errors.push("artifacts must be an object");
} else {
  const artifactKeys = ["commit_hash", "pr_url", "files_changed"];
  for (const key of Object.keys(artifacts)) {
    expect(artifactKeys.includes(key), `unexpected artifacts field: ${key}`);
  }
  for (const key of artifactKeys) {
    expect(Object.hasOwn(artifacts, key), `missing artifacts field: ${key}`);
  }
  expect(artifacts.commit_hash === null || typeof artifacts.commit_hash === "string", "artifacts.commit_hash must be null or a string");
  expect(artifacts.pr_url === null || /^https?:\/\//.test(artifacts.pr_url), "artifacts.pr_url must be null or an http(s) URL");
  expect(Array.isArray(artifacts.files_changed), "artifacts.files_changed must be an array");
  for (const [index, value] of (artifacts.files_changed || []).entries()) {
    expect(typeof value === "string", `artifacts.files_changed[${index}] must be a string`);
  }
}

const metrics = payload.metrics;
if (!isPlainObject(metrics)) {
  errors.push("metrics must be an object");
} else {
  const requiredMetricKeys = ["duration_ms", "tokens_used"];
  const allowedMetricKeys = ["duration_ms", "tokens_used", "token_usage"];
  for (const key of Object.keys(metrics)) {
    expect(allowedMetricKeys.includes(key), `unexpected metrics field: ${key}`);
  }
  for (const key of requiredMetricKeys) {
    expect(Object.hasOwn(metrics, key), `missing metrics field: ${key}`);
  }
  expect(isInteger(metrics.duration_ms) && metrics.duration_ms >= 0, "metrics.duration_ms must be an integer >= 0");
  expect(metrics.tokens_used === null || (isInteger(metrics.tokens_used) && metrics.tokens_used >= 0), "metrics.tokens_used must be null or an integer >= 0");

  const allowedTokenUsageSources = new Set(["codex_api", "cursor_api", "estimated", "unavailable"]);
  if (Object.hasOwn(metrics, "token_usage") && metrics.token_usage !== null) {
    const tu = metrics.token_usage;
    expect(isPlainObject(tu), "metrics.token_usage must be an object or null");
    if (isPlainObject(tu)) {
      const allowedTuKeys = new Set(["input_tokens", "output_tokens", "total_tokens", "source"]);
      for (const key of Object.keys(tu)) {
        expect(allowedTuKeys.has(key), `unexpected metrics.token_usage field: ${key}`);
      }
      for (const key of allowedTuKeys) {
        expect(Object.hasOwn(tu, key), `missing metrics.token_usage field: ${key}`);
      }
      expect(isInteger(tu.input_tokens) && tu.input_tokens >= 0, "metrics.token_usage.input_tokens must be an integer >= 0");
      expect(isInteger(tu.output_tokens) && tu.output_tokens >= 0, "metrics.token_usage.output_tokens must be an integer >= 0");
      expect(isInteger(tu.total_tokens) && tu.total_tokens >= 0, "metrics.token_usage.total_tokens must be an integer >= 0");
      expect(allowedTokenUsageSources.has(tu.source), "metrics.token_usage.source must be codex_api, cursor_api, estimated, or unavailable");
    }
  }
}

if (payload.outcome === "success") {
  expect(payload.exit_code === 0, "success outcome must use exit_code 0");
  expect(payload.failure_category === null, "success outcome must use failure_category null");
  expect(payload.retryable === false, "success outcome must not be retryable");
  expect(payload.handoff_required === false, "success outcome must not require handoff");
  expect(payload.handoff === null, "success outcome must use handoff null");
}

if (payload.outcome === "human_required") {
  expect(payload.exit_code === 20, "human_required outcome must use exit_code 20");
  expect(payload.failure_category === "ambiguous_requirements", "human_required outcome must use ambiguous_requirements");
  expect(payload.retryable === false, "human_required outcome must not be retryable");
  expect(payload.handoff_required === true, "human_required outcome must set handoff_required=true");
  expect(isPlainObject(payload.handoff), "human_required outcome must include a handoff object");
}

if (payload.outcome === "failure") {
  expect(payload.exit_code !== 0, "failure outcome must not use exit_code 0");
  expect(payload.failure_category !== null, "failure outcome must set failure_category");
  expect(payload.exit_code !== 20, "failure outcome must not use exit_code 20");
}

if (payload.exit_code === 10) {
  expect(payload.outcome === "failure", "exit_code 10 must use outcome=failure");
  expect(payload.retryable === false, "exit_code 10 must use retryable=false");
}

if (payload.exit_code === 11) {
  expect(payload.outcome === "failure", "exit_code 11 must use outcome=failure");
  expect(payload.retryable === true, "exit_code 11 must use retryable=true");
}

if (payload.exit_code === 20) {
  expect(payload.outcome === "human_required", "exit_code 20 must use outcome=human_required");
}

if (payload.exit_code === 30) {
  expect(payload.outcome === "failure", "exit_code 30 must use outcome=failure");
  expect(payload.failure_category === "tool_contract_violation", "exit_code 30 must use failure_category=tool_contract_violation");
  expect(payload.retryable === false, "exit_code 30 must use retryable=false");
}

if (payload.retryable && payload.failure_category === "ambiguous_requirements") {
  errors.push("ambiguous_requirements cannot be retryable");
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

#!/usr/bin/env node

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = {
    until: "HEAD",
    output: "",
    sidecar: "",
    scope: [],
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--since":
        args.since = argv[++i] || "";
        break;
      case "--until":
        args.until = argv[++i] || "";
        break;
      case "--output":
        args.output = argv[++i] || "";
        break;
      case "--sidecar":
        args.sidecar = argv[++i] || "";
        break;
      case "--scope":
        args.scope.push(argv[++i] || "");
        break;
      case "--help":
      case "-h":
        process.stdout.write(
          [
            "Usage: scripts/generate-release-notes.js --since <ref> [options]",
            "",
            "Options:",
            "  --since <ref>    Required start ref (commit or tag)",
            "  --until <ref>    End ref (default: HEAD)",
            "  --scope <path>   Optional path filter (repeatable)",
            "  --output <path>  Optional markdown output path",
            "  --sidecar <path> Optional JSON sidecar output path",
          ].join("\n"),
        );
        process.exit(0);
      default:
        fail(`unknown argument: ${arg}`);
    }
  }

  if (!args.since) {
    fail("--since is required");
  }

  args.scope = args.scope.filter(Boolean);
  return args;
}

function git(args, extra = {}) {
  return execFileSync("git", args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...extra,
  }).trimEnd();
}

function ensureRef(ref) {
  try {
    git(["rev-parse", "--verify", ref]);
  } catch {
    fail(`invalid git ref: ${ref}`);
  }
}

function normalizeTopDirectory(file) {
  if (!file) return "root";
  const top = file.split("/")[0];
  return top || "root";
}

function collectCommitRecords(rangeArgs) {
  const raw = git([
    "log",
    "--format=%x1e%H%x1f%s%x1f%b%x1f%ct",
    "--name-only",
    ...rangeArgs,
  ]);

  return raw
    .split("\x1e")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separatorIndex = entry.indexOf("\n\n");
      const header =
        separatorIndex >= 0 ? entry.slice(0, separatorIndex) : entry;
      const fileLines =
        separatorIndex >= 0 ? entry.slice(separatorIndex + 2) : "";
      const firstField = header.indexOf("\x1f");
      const secondField = header.indexOf("\x1f", firstField + 1);
      const lastField = header.lastIndexOf("\x1f");
      const sha = firstField >= 0 ? header.slice(0, firstField) : "";
      const subject =
        firstField >= 0 && secondField >= 0
          ? header.slice(firstField + 1, secondField)
          : "";
      const body =
        secondField >= 0 && lastField >= 0
          ? header.slice(secondField + 1, lastField)
          : "";
      const timestamp =
        lastField >= 0 ? header.slice(lastField + 1).trim() : "0";
      const files = fileLines
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean);
      return {
        sha,
        subject: subject.trim(),
        body: body.trim(),
        timestamp: Number(timestamp) || 0,
        files,
      };
    });
}

function scoreCommit(commit) {
  const text = `${commit.subject}\n${commit.body}`.toLowerCase();
  let score = 0;

  if (/breaking|migration|data loss/.test(text)) score += 10;
  if (/security|auth|billing|payment|privacy/.test(text)) score += 8;
  if (/perf|performance/.test(text)) score += 6;
  if (/fix|bug|regression/.test(text)) score += 5;
  if (/feat|add|introduce|implement/.test(text)) score += 4;
  if (/refactor|cleanup/.test(text)) score += 2;
  if (/docs|readme/.test(text)) score += 1;
  score += Math.min(commit.files.length, 5);

  return score;
}

function extractIssueRefs(text) {
  const matches = text.match(/N43-\d+/g) || [];
  return [...new Set(matches)];
}

function summarizeSubjects(commits) {
  return [...new Set(commits.map((commit) => commit.subject).filter(Boolean))].slice(0, 2);
}

function summarizeFiles(commits) {
  const counts = new Map();
  for (const commit of commits) {
    for (const file of commit.files) {
      const top = normalizeTopDirectory(file);
      counts.set(top, (counts.get(top) || 0) + 1);
    }
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, 3)
    .map(([name]) => name);
}

function buildGroups(commits) {
  const groups = new Map();

  for (const commit of commits) {
    const issueRefs = extractIssueRefs(`${commit.subject}\n${commit.body}`);
    const key = issueRefs[0] || normalizeTopDirectory(commit.files[0] || commit.subject);
    const existing = groups.get(key) || {
      key,
      commits: [],
      issueRefs: new Set(),
      files: new Set(),
      score: 0,
      risky: false,
    };
    existing.commits.push(commit);
    issueRefs.forEach((ref) => existing.issueRefs.add(ref));
    commit.files.forEach((file) => existing.files.add(file));
    existing.score += scoreCommit(commit);
    existing.risky =
      existing.risky ||
      /breaking|security|auth|billing|payment|migration|data loss/i.test(
        `${commit.subject}\n${commit.body}`,
      );
    groups.set(key, existing);
  }

  return [...groups.values()]
    .map((group) => {
      const subjects = summarizeSubjects(group.commits);
      const directories = summarizeFiles(group.commits);
      const commitsSorted = [...group.commits].sort((a, b) => b.timestamp - a.timestamp);
      const title =
        [...group.issueRefs][0] ||
        subjects[0] ||
        directories[0] ||
        group.key;
      return {
        key: group.key,
        title,
        score: group.score,
        risky: group.risky,
        commitCount: group.commits.length,
        issueRefs: [...group.issueRefs].sort(),
        files: [...group.files].sort(),
        topDirectories: directories,
        highlights: subjects,
        commits: commitsSorted.map((commit) => ({
          sha: commit.sha,
          subject: commit.subject,
          files: commit.files,
        })),
      };
    })
    .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
}

function buildMarkdown(args, groups, allCommits) {
  const critical = groups.filter((group) => group.risky);
  const topLimit = critical.length > 4 ? critical.length : 4;
  const topGroups = groups.slice(0, topLimit);
  const overflow = groups.slice(topLimit);

  const summary =
    topGroups.length === 0
      ? "No changes found in the requested range."
      : `Summarized ${allCommits.length} commits into ${topGroups.length} high-signal change groups.`;

  const lines = [];
  lines.push("# Release Notes");
  lines.push("");
  lines.push("## Summary");
  lines.push(summary);
  lines.push("");
  lines.push("## Source Range");
  lines.push(`- \`${args.since}\` -> \`${args.until}\``);
  if (args.scope.length > 0) {
    lines.push(`- Scope filter: ${args.scope.map((scope) => `\`${scope}\``).join(", ")}`);
  }
  lines.push("");
  lines.push("## Top Changes");

  for (const group of topGroups) {
    lines.push(`### ${group.title}`);
    lines.push(`- Changes: ${group.highlights.join(" | ") || "See underlying commits."}`);
    lines.push(
      `- Scope: ${group.commitCount} commit(s); primary areas ${group.topDirectories.map((dir) => `\`${dir}\``).join(", ") || "`root`"}.`,
    );
    lines.push(
      `- Traceability: ${group.issueRefs.length > 0 ? group.issueRefs.join(", ") : "no issue refs"}; commits ${group.commits
        .slice(0, 4)
        .map((commit) => `\`${commit.sha.slice(0, 7)}\``)
        .join(", ")}.`,
    );
    if (group.risky) {
      lines.push("- Risk: review this group for breaking, security, or migration-sensitive behavior.");
    }
    lines.push("");
  }

  if (critical.length > 4) {
    lines.push("## Critical Additions");
    for (const group of critical.slice(4)) {
      lines.push(`- ${group.title}`);
    }
    lines.push("");
  }

  lines.push("## Also Changed");
  if (overflow.length === 0) {
    lines.push("- No additional lower-priority groups.");
  } else {
    for (const group of overflow.slice(0, 8)) {
      lines.push(
        `- ${group.title}: ${group.highlights[0] || "additional changes"} (${group.commitCount} commit${group.commitCount === 1 ? "" : "s"})`,
      );
    }
  }
  lines.push("");

  return lines.join("\n");
}

function ensureParentDir(filePath) {
  if (!filePath) return;
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  ensureRef(args.since);
  ensureRef(args.until);

  const rangeArgs = [`${args.since}..${args.until}`];
  if (args.scope.length > 0) {
    rangeArgs.push("--", ...args.scope);
  }

  const commits = collectCommitRecords(rangeArgs);
  const groups = buildGroups(commits);
  const markdown = buildMarkdown(args, groups, commits);
  const sidecar = {
    generatedAt: new Date().toISOString(),
    sourceRange: {
      since: args.since,
      until: args.until,
      scope: args.scope,
    },
    commitCount: commits.length,
    groupCount: groups.length,
    groups,
  };

  if (args.output) {
    ensureParentDir(args.output);
    fs.writeFileSync(args.output, `${markdown}\n`);
  }

  if (args.sidecar) {
    ensureParentDir(args.sidecar);
    fs.writeFileSync(args.sidecar, `${JSON.stringify(sidecar, null, 2)}\n`);
  }

  process.stdout.write(`${markdown}\n`);
}

main();

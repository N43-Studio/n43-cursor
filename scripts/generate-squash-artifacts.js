#!/usr/bin/env node

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const VALID_PHASES = new Set(["pre", "post"]);
const VALID_STATUSES = new Set(["pass", "fail", "skipped"]);
const DEFAULT_VALIDATION_RESULTS = {
  lint: "skipped",
  typecheck: "skipped",
  test: "skipped",
  build: "skipped",
};

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

function usage() {
  process.stdout.write(
    [
      "Usage: node scripts/generate-squash-artifacts.js --phase <pre|post> --branch <branch> [options]",
      "",
      "Options:",
      "  --phase <pre|post>                 Artifact phase to run",
      "  --branch <branch>                  Original branch to squash",
      "  --parent <branch>                  Parent branch (default: upstream branch, then main/master)",
      "  --merge-base <sha>                 Explicit merge base override",
      "  --squash-branch <branch>           Squash branch name (default: <branch>-squash)",
      "  --strategy <single|grouped|split>  Strategy label for artifacts (default: single)",
      "  --rationale <text>                 Squash rationale for plan/summary artifacts",
      "  --issue-id <id>                    Optional issue id, for example N43-473",
      "  --output-dir <path>                Artifact root directory (default: .ralph/squash-artifacts)",
      "  --validation-lint <status>         pass|fail|skipped (post phase only)",
      "  --validation-typecheck <status>    pass|fail|skipped (post phase only)",
      "  --validation-test <status>         pass|fail|skipped (post phase only)",
      "  --validation-build <status>        pass|fail|skipped (post phase only)",
      "  --help                             Show this help",
    ].join("\n"),
  );
}

function parseArgs(argv) {
  const args = {
    phase: "",
    branch: "",
    parent: "",
    mergeBase: "",
    squashBranch: "",
    strategy: "single",
    rationale: "",
    issueId: "",
    outputDir: ".ralph/squash-artifacts",
    validationResults: { ...DEFAULT_VALIDATION_RESULTS },
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    switch (arg) {
      case "--phase":
        args.phase = argv[++i] || "";
        break;
      case "--branch":
        args.branch = argv[++i] || "";
        break;
      case "--parent":
        args.parent = argv[++i] || "";
        break;
      case "--merge-base":
        args.mergeBase = argv[++i] || "";
        break;
      case "--squash-branch":
        args.squashBranch = argv[++i] || "";
        break;
      case "--strategy":
        args.strategy = argv[++i] || "";
        break;
      case "--rationale":
        args.rationale = argv[++i] || "";
        break;
      case "--issue-id":
        args.issueId = argv[++i] || "";
        break;
      case "--output-dir":
        args.outputDir = argv[++i] || "";
        break;
      case "--validation-lint":
        args.validationResults.lint = argv[++i] || "";
        break;
      case "--validation-typecheck":
        args.validationResults.typecheck = argv[++i] || "";
        break;
      case "--validation-test":
        args.validationResults.test = argv[++i] || "";
        break;
      case "--validation-build":
        args.validationResults.build = argv[++i] || "";
        break;
      case "--help":
      case "-h":
        usage();
        process.exit(0);
      default:
        fail(`unknown argument: ${arg}`);
    }
  }

  if (!VALID_PHASES.has(args.phase)) {
    fail("--phase must be one of: pre, post");
  }
  if (!args.branch) {
    fail("--branch is required");
  }
  if (!args.outputDir) {
    fail("--output-dir cannot be empty");
  }
  if (!args.strategy) {
    fail("--strategy cannot be empty");
  }

  for (const [key, value] of Object.entries(args.validationResults)) {
    if (!VALID_STATUSES.has(value)) {
      fail(`--validation-${key} must be one of: pass, fail, skipped`);
    }
  }

  return args;
}

function git(args, options = {}) {
  try {
    return execFileSync("git", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      ...options,
    }).trimEnd();
  } catch (error) {
    const stderr = error && error.stderr ? String(error.stderr).trim() : "";
    const message = stderr || `git ${args.join(" ")} failed`;
    fail(message);
  }
}

function gitSuccess(args) {
  try {
    execFileSync("git", args, {
      stdio: ["ignore", "ignore", "ignore"],
    });
    return true;
  } catch {
    return false;
  }
}

function ensureGitRepository() {
  if (!gitSuccess(["rev-parse", "--is-inside-work-tree"])) {
    fail("not in a git repository");
  }
}

function ensureCommitRef(ref, label) {
  if (!gitSuccess(["rev-parse", "--verify", `${ref}^{commit}`])) {
    fail(`${label} does not resolve to a commit: ${ref}`);
  }
}

function extractIssueRefs(text) {
  const matches = text.match(/\bN43-\d+\b/g) || [];
  return [...new Set(matches)];
}

function sanitizeBranchName(branch) {
  return branch.replace(/[^A-Za-z0-9._-]+/g, "__");
}

function ensureDirectory(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath, payload) {
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function readJsonIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function topDirectories(files) {
  return unique(
    files.map((file) => {
      const first = file.split("/")[0];
      return first || "root";
    }),
  ).sort();
}

function fallbackParentBranch(branch) {
  const upstream = git(["for-each-ref", "--format=%(upstream:short)", `refs/heads/${branch}`]);
  if (upstream) {
    return upstream.replace(/^origin\//, "");
  }
  if (gitSuccess(["show-ref", "--verify", "--quiet", "refs/heads/main"])) {
    return "main";
  }
  if (gitSuccess(["show-ref", "--verify", "--quiet", "refs/heads/master"])) {
    return "master";
  }
  fail(`unable to infer parent branch for ${branch}; pass --parent explicitly`);
}

function collectCommits(range) {
  const commitShasRaw = git(["rev-list", "--reverse", range]);
  const commitShas = commitShasRaw
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  return commitShas.map((sha) => {
    const subject = git(["show", "-s", "--format=%s", sha]).trim();
    const body = git(["show", "-s", "--format=%b", sha]).trim();
    const timestamp = Number(git(["show", "-s", "--format=%ct", sha]).trim()) || 0;
    const parents = git(["show", "-s", "--format=%P", sha])
      .split(" ")
      .map((value) => value.trim())
      .filter(Boolean);
    const files = git(["show", "--name-only", "--pretty=format:", sha])
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean);
    const issueRefs = extractIssueRefs(`${subject}\n${body}`);

    return {
      sha,
      subject,
      body,
      timestamp,
      parent_count: parents.length,
      files,
      issue_refs: issueRefs,
    };
  });
}

function countFileOverlaps(commits) {
  const overlaps = [];
  for (let i = 0; i < commits.length; i += 1) {
    const left = commits[i];
    const leftFiles = new Set(left.files);
    for (let j = i + 1; j < commits.length; j += 1) {
      const right = commits[j];
      const shared = right.files.filter((file) => leftFiles.has(file));
      if (shared.length > 0) {
        overlaps.push({
          left_sha: left.sha,
          right_sha: right.sha,
          shared_file_count: shared.length,
          shared_files_preview: shared.slice(0, 5),
        });
      }
    }
  }
  return overlaps;
}

function recommendStrategy(commits) {
  if (commits.length <= 1) {
    return {
      strategy: "single",
      reason: "one_commit_in_range",
    };
  }

  const mergeCommitCount = commits.filter((commit) => commit.parent_count > 1).length;
  if (mergeCommitCount > 0) {
    return {
      strategy: "single",
      reason: "merge_commits_present",
    };
  }

  const refsPerCommit = commits.map((commit) => commit.issue_refs.join(","));
  const uniqueRefsPerCommit = unique(refsPerCommit);
  if (uniqueRefsPerCommit.length === 1 && uniqueRefsPerCommit[0]) {
    return {
      strategy: "single",
      reason: "same_issue_reference_across_commits",
    };
  }

  const directories = topDirectories(commits.flatMap((commit) => commit.files));
  if (directories.length >= 2 && directories.length <= 3) {
    return {
      strategy: "grouped",
      reason: "limited_directory_clusters",
    };
  }

  return {
    strategy: "single",
    reason: "default_safe_choice",
  };
}

function buildPlanArtifact({
  branch,
  parentBranch,
  squashBranch,
  mergeBase,
  selectedStrategy,
  rationale,
  issueId,
  commits,
}) {
  const allFiles = commits.flatMap((commit) => commit.files);
  const allIssueRefs = unique(commits.flatMap((commit) => commit.issue_refs));
  const overlaps = countFileOverlaps(commits);
  const mergeCommitCount = commits.filter((commit) => commit.parent_count > 1).length;
  const recommendation = recommendStrategy(commits);

  return {
    artifact_version: "1.0",
    artifact_type: "squash_plan",
    generated_at: new Date().toISOString(),
    issue_id: issueId || null,
    branch,
    parent_branch: parentBranch,
    squash_branch: squashBranch,
    merge_base: mergeBase,
    commit_range: `${mergeBase}..${branch}`,
    commit_count: commits.length,
    selected_strategy: selectedStrategy,
    selected_strategy_rationale: rationale || null,
    recommended_strategy: recommendation.strategy,
    recommended_strategy_reason: recommendation.reason,
    merge_commit_count: mergeCommitCount,
    unique_issue_refs: allIssueRefs,
    top_directories: topDirectories(allFiles),
    file_overlap_pairs: overlaps,
    commits: commits.map((commit) => ({
      sha: commit.sha,
      subject: commit.subject,
      timestamp: commit.timestamp,
      files: commit.files,
      issue_refs: commit.issue_refs,
    })),
  };
}

function mapOldToNewCommits(oldCommits, newCommits) {
  if (newCommits.length === 0) {
    return oldCommits.map((oldCommit) => ({
      old_commit_sha: oldCommit.sha,
      old_commit_subject: oldCommit.subject,
      new_commit_shas: [],
      mapping_reason: "no_new_commits_found",
    }));
  }

  const newFileSets = newCommits.map((newCommit) => ({
    sha: newCommit.sha,
    subject: newCommit.subject,
    files: new Set(newCommit.files),
  }));

  return oldCommits.map((oldCommit) => {
    const oldFiles = new Set(oldCommit.files);
    const scored = newFileSets.map((candidate) => {
      let overlapCount = 0;
      for (const file of oldFiles) {
        if (candidate.files.has(file)) {
          overlapCount += 1;
        }
      }
      return {
        sha: candidate.sha,
        subject: candidate.subject,
        overlap_count: overlapCount,
      };
    });

    const maxOverlap = Math.max(...scored.map((entry) => entry.overlap_count));
    const selected =
      maxOverlap > 0
        ? scored.filter((entry) => entry.overlap_count === maxOverlap)
        : scored;

    return {
      old_commit_sha: oldCommit.sha,
      old_commit_subject: oldCommit.subject,
      new_commit_shas: selected.map((entry) => entry.sha),
      mapping_reason:
        maxOverlap > 0 ? "best_file_overlap" : "range_association_no_file_overlap",
    };
  });
}

function buildValidationSummary(validationResults) {
  const values = Object.values(validationResults);
  const failed = values.filter((value) => value === "fail").length;
  return {
    lint: validationResults.lint,
    typecheck: validationResults.typecheck,
    test: validationResults.test,
    build: validationResults.build,
    failed_count: failed,
    all_passed: failed === 0,
  };
}

function buildPrSummaryMarkdown({
  issueId,
  branch,
  squashBranch,
  parentBranch,
  strategy,
  rationale,
  oldCommitCount,
  newCommitCount,
  equivalence,
  validationResults,
  planPath,
  mappingPath,
  verificationPath,
}) {
  const statusLine = equivalence ? "PASS" : "FAIL";
  const lines = [];
  lines.push("# Squash PR Summary");
  lines.push("");
  if (issueId) {
    lines.push(`- Issue: ${issueId}`);
  }
  lines.push(`- Source branch: \`${branch}\``);
  lines.push(`- Squash branch: \`${squashBranch}\``);
  lines.push(`- Parent branch: \`${parentBranch}\``);
  lines.push(`- Strategy: \`${strategy}\``);
  lines.push("");
  lines.push("## Rationale");
  lines.push(rationale || "No explicit rationale was provided.");
  lines.push("");
  lines.push("## Rewrite Summary");
  lines.push(`- Commits before squash: ${oldCommitCount}`);
  lines.push(`- Commits after squash: ${newCommitCount}`);
  lines.push("");
  lines.push("## Verification");
  lines.push(`- Tree equivalence: ${statusLine}`);
  lines.push(`- lint: ${validationResults.lint}`);
  lines.push(`- typecheck: ${validationResults.typecheck}`);
  lines.push(`- test: ${validationResults.test}`);
  lines.push(`- build: ${validationResults.build}`);
  lines.push("");
  lines.push("## Artifacts");
  lines.push(`- Plan: \`${planPath}\``);
  lines.push(`- Commit mapping: \`${mappingPath}\``);
  lines.push(`- Verification: \`${verificationPath}\``);
  lines.push("");
  lines.push("## PR Body Snippet");
  lines.push("");
  lines.push("```markdown");
  lines.push(`### Squash Summary (${strategy})`);
  lines.push(`- Verified tree equivalence: ${statusLine}`);
  lines.push(`- Validation: lint=${validationResults.lint}, typecheck=${validationResults.typecheck}, test=${validationResults.test}, build=${validationResults.build}`);
  lines.push("```");
  lines.push("");
  return `${lines.join("\n")}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  ensureGitRepository();

  ensureCommitRef(args.branch, "branch");
  const parentBranch = args.parent || fallbackParentBranch(args.branch);
  ensureCommitRef(parentBranch, "parent branch");

  const squashBranch = args.squashBranch || `${args.branch}-squash`;
  const mergeBase = args.mergeBase || git(["merge-base", args.branch, parentBranch]).trim();
  ensureCommitRef(mergeBase, "merge base");

  const outputRoot = path.resolve(args.outputDir);
  const branchDir = path.join(outputRoot, sanitizeBranchName(args.branch));
  ensureDirectory(branchDir);

  const planPath = path.join(branchDir, "squash-plan.json");
  const mappingPath = path.join(branchDir, "commit-mapping.json");
  const verificationPath = path.join(branchDir, "verification.json");
  const prSummaryJsonPath = path.join(branchDir, "pr-summary.json");
  const prSummaryMarkdownPath = path.join(branchDir, "pr-summary.md");

  const oldRange = `${mergeBase}..${args.branch}`;
  const oldCommits = collectCommits(oldRange);

  const planArtifact = buildPlanArtifact({
    branch: args.branch,
    parentBranch,
    squashBranch,
    mergeBase,
    selectedStrategy: args.strategy,
    rationale: args.rationale,
    issueId: args.issueId,
    commits: oldCommits,
  });
  writeJson(planPath, planArtifact);

  if (args.phase === "pre") {
    process.stdout.write(
      `${JSON.stringify(
        {
          phase: "pre",
          issue_id: args.issueId || null,
          branch: args.branch,
          squash_branch: squashBranch,
          plan_path: planPath,
          commit_count: oldCommits.length,
        },
        null,
        2,
      )}\n`,
    );
    return;
  }

  ensureCommitRef(squashBranch, "squash branch");
  const newRange = `${mergeBase}..${squashBranch}`;
  const newCommits = collectCommits(newRange);
  const oldToNew = mapOldToNewCommits(oldCommits, newCommits);

  const diffFiles = git(["diff", "--name-only", args.branch, squashBranch])
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const originalTree = git(["rev-parse", `${args.branch}^{tree}`]).trim();
  const squashTree = git(["rev-parse", `${squashBranch}^{tree}`]).trim();
  const equivalent = diffFiles.length === 0 && originalTree === squashTree;

  const validationSummary = buildValidationSummary(args.validationResults);

  const mappingArtifact = {
    artifact_version: "1.0",
    artifact_type: "commit_mapping",
    generated_at: new Date().toISOString(),
    issue_id: args.issueId || null,
    branch: args.branch,
    squash_branch: squashBranch,
    merge_base: mergeBase,
    old_commit_count: oldCommits.length,
    new_commit_count: newCommits.length,
    old_to_new: oldToNew,
  };
  writeJson(mappingPath, mappingArtifact);

  const verificationArtifact = {
    artifact_version: "1.0",
    artifact_type: "verification",
    generated_at: new Date().toISOString(),
    issue_id: args.issueId || null,
    branch: args.branch,
    squash_branch: squashBranch,
    tree_equivalence: {
      equivalent,
      original_tree: originalTree,
      squash_tree: squashTree,
      differing_files_count: diffFiles.length,
      differing_files: diffFiles,
    },
    validation_results: validationSummary,
  };
  writeJson(verificationPath, verificationArtifact);

  const priorPlan = readJsonIfExists(planPath);
  const strategy = args.strategy || priorPlan?.selected_strategy || "single";
  const rationale = args.rationale || priorPlan?.selected_strategy_rationale || "";

  const prSummaryMarkdown = buildPrSummaryMarkdown({
    issueId: args.issueId,
    branch: args.branch,
    squashBranch,
    parentBranch,
    strategy,
    rationale,
    oldCommitCount: oldCommits.length,
    newCommitCount: newCommits.length,
    equivalence: equivalent,
    validationResults: validationSummary,
    planPath,
    mappingPath,
    verificationPath,
  });

  const prSummaryJson = {
    artifact_version: "1.0",
    artifact_type: "pr_summary",
    generated_at: new Date().toISOString(),
    issue_id: args.issueId || null,
    branch: args.branch,
    squash_branch: squashBranch,
    parent_branch: parentBranch,
    merge_base: mergeBase,
    strategy,
    rationale: rationale || null,
    commits_before_squash: oldCommits.length,
    commits_after_squash: newCommits.length,
    tree_equivalence_verified: equivalent,
    validation_results: validationSummary,
    artifact_paths: {
      plan: planPath,
      mapping: mappingPath,
      verification: verificationPath,
      pr_summary_markdown: prSummaryMarkdownPath,
    },
    pr_body_snippet_markdown: [
      `### Squash Summary (${strategy})`,
      `- Verified tree equivalence: ${equivalent ? "PASS" : "FAIL"}`,
      `- Validation: lint=${validationSummary.lint}, typecheck=${validationSummary.typecheck}, test=${validationSummary.test}, build=${validationSummary.build}`,
    ].join("\n"),
  };
  writeJson(prSummaryJsonPath, prSummaryJson);
  fs.writeFileSync(prSummaryMarkdownPath, prSummaryMarkdown, "utf8");

  process.stdout.write(
    `${JSON.stringify(
      {
        phase: "post",
        issue_id: args.issueId || null,
        branch: args.branch,
        squash_branch: squashBranch,
        equivalent,
        plan_path: planPath,
        mapping_path: mappingPath,
        verification_path: verificationPath,
        pr_summary_json_path: prSummaryJsonPath,
        pr_summary_markdown_path: prSummaryMarkdownPath,
      },
      null,
      2,
    )}\n`,
  );
}

main();

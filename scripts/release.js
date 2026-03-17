const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const bump = process.argv[2] || "patch";
if (!["patch", "minor", "major"].includes(bump)) {
  console.error(`Usage: node scripts/release.js [patch|minor|major]`);
  process.exit(1);
}

function run(cmd, opts = {}) {
  console.log(`$ ${cmd}`);
  return execSync(cmd, {
    encoding: "utf8",
    stdio: opts.silent ? "pipe" : "inherit",
    ...opts,
  });
}

function runSilent(cmd) {
  return execSync(cmd, { encoding: "utf8", stdio: "pipe" }).trim();
}

function askClaude(promptText) {
  const tmpFile = path.join(__dirname, "..", ".tmp-prompt");
  fs.writeFileSync(tmpFile, promptText);
  try {
    const result = execSync(`cat "${tmpFile}" | claude --print --model haiku`, {
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
      timeout: 60000,
    }).trim();
    fs.unlinkSync(tmpFile);
    return result;
  } catch {
    try {
      fs.unlinkSync(tmpFile);
    } catch {}
    return null;
  }
}

// --- Read current version from mix.exs ---
const mixExs = fs.readFileSync("mix.exs", "utf8");
const versionMatch = mixExs.match(/@version\s+"(\d+\.\d+\.\d+)"/);
if (!versionMatch) {
  console.error("Could not find @version in mix.exs");
  process.exit(1);
}
const currentVersion = versionMatch[1];
const [major, minor, patch] = currentVersion.split(".").map(Number);
const nextVersion =
  bump === "major"
    ? `${major + 1}.0.0`
    : bump === "minor"
      ? `${major}.${minor + 1}.0`
      : `${major}.${minor}.${patch + 1}`;

console.log(`\n=== ${currentVersion} -> ${nextVersion} (${bump}) ===\n`);

// --- Step 1: Stage & commit any pending changes ---
console.log("\n=== Staging changes ===\n");
run("git add -A");

const hasChanges = (() => {
  try {
    runSilent("git diff --cached --quiet");
    return false;
  } catch {
    return true;
  }
})();

if (hasChanges) {
  const diffStat = runSilent("git diff --cached --stat");
  const diffContent = runSilent("git diff --cached").slice(0, 8000);

  console.log("\n=== Generating commit message ===\n");
  const commitMsg =
    askClaude(
      [
        "Generate a git commit message for these changes.",
        "",
        "Diff stat:",
        diffStat,
        "",
        "Diff (truncated):",
        diffContent,
        "",
        "Rules:",
        "- One line, max 72 characters",
        "- Conventional commit: type(scope): description",
        "- Types: feat, fix, chore, refactor, docs, ci",
        "- No period at end",
        "- Output ONLY the message, nothing else",
      ].join("\n"),
    ) || "chore: pre-release changes";

  const cleanMsg = commitMsg.split("\n")[0].replace(/^["']|["']$/g, "");
  console.log(`Commit message: ${cleanMsg}\n`);

  const msgFile = path.join(__dirname, "..", ".commit-msg");
  fs.writeFileSync(msgFile, cleanMsg);
  run(`git commit -F .commit-msg`);
  fs.unlinkSync(msgFile);
} else {
  console.log("Working tree clean, no commit needed.\n");
}

// --- Step 2: Generate changelog ---
console.log(`\n=== Generating changelog for v${nextVersion} ===\n`);

let lastTag;
try {
  lastTag = runSilent("git describe --tags --abbrev=0 HEAD");
} catch {
  lastTag = runSilent("git rev-list --max-parents=0 HEAD");
}

const commits = runSilent(`git log ${lastTag}..HEAD --oneline`);
const diffStat = runSilent(`git diff ${lastTag}..HEAD --stat`);
const diff = runSilent(`git diff ${lastTag}..HEAD -- lib/ mix.exs`).slice(
  0,
  12000,
);

const changelogPath = "CHANGELOG.md";
let changelog;
try {
  changelog = fs.readFileSync(changelogPath, "utf8");
} catch {
  changelog = "# Changelog\n";
  fs.writeFileSync(changelogPath, changelog);
}

const changelogEntry = askClaude(
  [
    `Generate a changelog entry for v${nextVersion} of the "HoloDev" Elixir package.`,
    "",
    `Commits since ${lastTag}:`,
    commits,
    "",
    "Diff stat:",
    diffStat,
    "",
    "Code diff (truncated):",
    diff,
    "",
    `Output this exact format:`,
    "",
    `## ${nextVersion}`,
    "",
    "Then categorize changes under these headings (omit empty ones):",
    "### New Features",
    "### Improvements",
    "### Fixes",
    "",
    "CRITICAL RULES:",
    "- Output ONLY the markdown changelog entry",
    "- Do NOT explain, analyze, or add commentary",
    "- Do NOT wrap in code fences",
    "- Do NOT use brackets in version heading",
    "- One concise line per change",
    "- Bold feature names with **name**",
  ].join("\n"),
);

if (changelogEntry) {
  let cleaned = changelogEntry
    .replace(/^```(?:markdown)?\n?/, "")
    .replace(/\n?```$/, "")
    .trim();

  if (!cleaned.startsWith(`## ${nextVersion}`)) {
    const idx = cleaned.indexOf(`## ${nextVersion}`);
    if (idx > 0) cleaned = cleaned.slice(idx);
    else cleaned = `## ${nextVersion}\n\n${cleaned}`;
  }

  const updated = changelog.replace(
    "# Changelog\n",
    `# Changelog\n\n${cleaned}\n`,
  );
  fs.writeFileSync(changelogPath, updated);
  console.log(cleaned);
} else {
  const entry = `## ${nextVersion}\n\n${commits
    .split("\n")
    .map((c) => `- ${c.replace(/^[a-f0-9]+ /, "")}`)
    .join("\n")}`;
  const updated = changelog.replace(
    "# Changelog\n",
    `# Changelog\n\n${entry}\n`,
  );
  fs.writeFileSync(changelogPath, updated);
  console.log(entry);
}

// --- Step 3: Bump version in mix.exs ---
console.log(`\n=== Bumping mix.exs version to ${nextVersion} ===\n`);
const updatedMixExs = mixExs.replace(
  `@version "${currentVersion}"`,
  `@version "${nextVersion}"`,
);
fs.writeFileSync("mix.exs", updatedMixExs);

// --- Step 4: Commit, tag, push ---
run("git add mix.exs CHANGELOG.md");
run(`git commit -m "v${nextVersion}"`);
run(`git tag v${nextVersion}`);

console.log(`\n=== Publishing v${nextVersion} ===\n`);
run("git push");
run("git push --tags");

// --- Step 5: GitHub release ---
const finalChangelog = fs.readFileSync(changelogPath, "utf8");
const escaped = nextVersion.replace(/\./g, "\\.");
const match = finalChangelog.match(
  new RegExp(`## \\[?v?${escaped}\\]?\\n([\\s\\S]*?)(?=\\n## |$)`),
);
const releaseNotes = match ? match[1].trim() : `Release v${nextVersion}`;

const notesFile = path.join(__dirname, "..", ".release-notes");
fs.writeFileSync(notesFile, releaseNotes);
run(`gh release create v${nextVersion} --notes-file .release-notes`);
fs.unlinkSync(notesFile);

console.log(`\n=== Released v${nextVersion} ===\n`);
console.log(
  "Hex publish will happen automatically via GitHub Actions on tag push.",
);
console.log("Or run manually: mix hex.publish");

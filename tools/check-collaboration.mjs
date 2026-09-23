#!/usr/bin/env node
// Read-only startup check shared by every developer and agent harness.
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import os from 'node:os';

const repository = 'fumbleforce/battlebots';
const board = 2;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('Usage: node tools/check-collaboration.mjs [--issue NUMBER]\nRead-only: verifies local gh access and displays the board, current claims and task.');
  process.exit(0);
}
if (args.length && (args.length !== 2 || args[0] !== '--issue' || !/^[1-9]\d*$/.test(args[1]))) {
  console.error('Usage: node tools/check-collaboration.mjs [--issue NUMBER]');
  process.exit(2);
}
const selected = args.length ? Number(args[1]) : null;
function run(binary, argv) {
  const result = spawnSync(binary, argv, { cwd: root, encoding: 'utf8', timeout: 60000,
    maxBuffer: 16 * 1024 * 1024, env: { ...process.env, GH_PROMPT_DISABLED: '1', GH_PAGER: 'cat' } });
  if (result.error || result.status !== 0) {
    if (result.error?.code === 'ENOENT' && binary === 'gh') {
      throw new Error('GitHub CLI is missing. Install gh from https://cli.github.com, then run gh auth login locally.');
    }
    // Do not echo authentication environment variables or credential output.
    throw new Error(`${binary} ${argv[0]} failed. Check network/repository access and run gh auth status, then gh auth login locally if required.`);
  }
  return result.stdout.trim();
}
function api(endpoint, ...flags) {
  return JSON.parse(run('gh', ['api', endpoint, ...flags]));
}
function showIssue(number, heading) {
  const item = api(`repos/${repository}/issues/${number}`);
  if (item.pull_request) throw new Error(`#${number} is a pull request; select a task issue.`);
  const comments = api(`repos/${repository}/issues/${number}/comments?per_page=100`, '--paginate', '--slurp').flat();
  console.log(`\n${heading}: #${number} ${item.title} [${item.state}]\n${item.html_url}\n${item.body ?? ''}`);
  console.log(`Recent comments (${Math.min(comments.length, 10)} of ${comments.length}; full history at the link):`);
  for (const comment of comments.slice(-10)) {
    console.log(`\n${comment.created_at} ${comment.user.login} ${comment.html_url}\n${comment.body}`);
  }
  return item;
}
try {
  const version = run('gh', ['--version']).split('\n')[0];
  const login = api('user').login;
  const repo = api(`repos/${repository}`);
  if (!repo.has_issues || !(repo.permissions?.push || repo.permissions?.maintain || repo.permissions?.admin)) {
    throw new Error(`Authenticated as ${login}, but enabled issues and repository write access are required for ${repository}.`);
  }
  const branch = run('git', ['branch', '--show-current']) || '(detached HEAD)';
  const commit = run('git', ['rev-parse', '--short', 'HEAD']);
  const issues = api(`repos/${repository}/issues?state=open&per_page=100`, '--paginate', '--slurp')
    .flat().filter(issue => !issue.pull_request);
  console.log(`GH ACCESS VERIFIED ${new Date().toISOString()}\n${version}\nAccount: ${login}; repository: ${repository}; write access: yes\nMachine: ${os.hostname()}; checkout: ${root}\nBranch: ${branch}; base: ${commit}`);
  console.log('\nOpen task status (labels route work; they are not a session claim):');
  for (const issue of issues.filter(issue => issue.number !== board)) {
    console.log(`#${issue.number} ${issue.title} | ${issue.labels.map(label => label.name).join(', ')} | updated ${issue.updated_at}`);
  }
  showIssue(board, 'Shared coordination board');
  const active = issues.filter(issue => issue.number !== board && issue.labels.some(label =>
    ['status:active', 'status:blocked'].includes(label.name)));
  for (const issue of active) showIssue(issue.number, 'Current reservation/dependency');
  let target = selected ? issues.find(issue => issue.number === selected) : null;
  if (selected && !active.some(issue => issue.number === selected) && selected !== board) {
    target = showIssue(selected, 'Selected task');
  }
  if (selected && (!target || target.state !== 'open' || selected === board)) {
    throw new Error('Select an open task issue; create or explicitly reopen the appropriate task before new implementation.');
  }
  console.log('\nCOLLABORATION PREFLIGHT PASS — access/read checks only; this does not claim work or approve overlapping paths.');
  console.log('Read the displayed claims, post your session/path claim and UTC next update, then re-read task + board before editing.');
} catch (error) {
  console.error(`COLLABORATION PREFLIGHT FAILED: ${error.message}`);
  process.exitCode = 1;
}

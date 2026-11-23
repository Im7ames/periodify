import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile, readdir, writeFile } from 'node:fs/promises';

const tag = process.env.TAG;
const repo = process.env.GITHUB_REPOSITORY;
const runId = process.env.GITHUB_RUN_ID;
const mode = process.argv[2];
if (!/^v\d+\.\d+\.\d+$/.test(tag ?? '')) throw new Error('Invalid release tag');
if (!/^[\w.-]+\/[\w.-]+$/.test(repo ?? '')) throw new Error('Invalid repository');
if (mode !== '--prepare' && mode !== '--publish') throw new Error('Use --prepare or --publish');

const origin = `https://github.com/${repo}`;
const download = (name) => `${origin}/releases/download/${tag}/${name}`;
const packages = {
  Android: 'periodify-android.apk',
  'Android App Bundle': 'periodify-android.aab',
  'Wear OS': 'periodify-wear-os.apk',
  'Windows x64': 'periodify-windows.exe',
  macOS: 'periodify-macos.dmg',
  'Linux x64': 'periodify-linux.deb',
  Web: 'periodify-web.zip',
};
const required = [
  packages.Android, packages['Android App Bundle'], packages['Wear OS'],
  packages['Linux x64'], packages.Web, 'periodify-linux.deb.asc', 'linux-signing-key.asc',
];
const optional = [packages['Windows x64'], packages.macOS];
const checkFile = 'SHA256SUMS.txt';
const updateFile = 'updates.json';
const files = new Set(await readdir('artifacts'));
for (const name of required) {
  if (!files.has(name)) throw new Error(`Required release file missing: ${name}`);
}
const attached = [...required, ...optional.filter((name) => files.has(name))].sort();
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');

if (mode === '--prepare') {
  const assets = await Promise.all(attached.map(async (name) => {
    const bytes = await readFile(`artifacts/${name}`);
    return { name, size: bytes.length, sha256: hash(bytes), url: download(name) };
  }));
  const manifest = { schema: 1, version: tag.slice(1), releaseUrl: `${origin}/releases/tag/${tag}`, assets };
  await writeFile(`artifacts/${checkFile}`, assets.map((a) => `${a.sha256}  ${a.name}\n`).join(''));
  await writeFile(`artifacts/${updateFile}`, JSON.stringify(manifest, null, 2) + '\n');
} else {
  const manifest = JSON.parse(await readFile(`artifacts/${updateFile}`, 'utf8'));
  if (manifest.version !== tag.slice(1)) throw new Error('Update manifest version mismatch');
  const gh = (args) => execFileSync('gh', args, { encoding: 'utf8' });
  const path = (name) => `artifacts/${name}`;

  // Upload and verify packages before pointing the update manifest at them.
  gh(['release', 'upload', tag, ...attached.map(path), path(checkFile), '--clobber']);
  for (const name of [...attached, checkFile]) {
    const response = await fetch(download(name), { signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`Could not download ${name}: HTTP ${response.status}`);
    const published = Buffer.from(await response.arrayBuffer());
    if (hash(published) !== hash(await readFile(path(name)))) {
      throw new Error(`Release checksum mismatch: ${name}`);
    }
  }
  gh(['release', 'upload', tag, path(updateFile), '--clobber']);

  const statusUrl = `${origin}/actions/runs/${runId}`;
  const rows = Object.entries(packages).map(([platform, name]) => {
    const cell = files.has(name) ? `[${name}](${download(name)})` : `Unavailable · [build status](${statusUrl})`;
    return `| ${platform} | ${cell} |`;
  });
  const table = [
    '<!-- downloads -->',
    '| Platform | Download |',
    '| --- | --- |',
    ...rows,
    '',
    'Windows and macOS downloads require trusted signing. See the [release setup](' + origin + '/blob/' + tag + '/docs/RELEASING.md).',
    '',
    `Checksums: [${checkFile}](${download(checkFile)}). Update manifest: [${updateFile}](${download(updateFile)}).`,
    '<!-- /downloads -->',
  ].join('\n');
  const release = JSON.parse(gh(['release', 'view', tag, '--json', 'body']));
  const notes = release.body.replace(/<!-- downloads -->[\s\S]*?<!-- \/downloads -->/g, '').trim();
  await writeFile('release-body.md', `${notes}\n\n${table}\n`);
  gh(['release', 'edit', tag, '--notes-file', 'release-body.md']);

  const verified = JSON.parse(gh(['release', 'view', tag, '--json', 'assets,body']));
  for (const name of [...attached, checkFile, updateFile]) {
    if (!verified.assets.some((asset) => asset.name === name)) throw new Error(`Release asset missing: ${name}`);
  }
  if (!verified.body.includes(table)) throw new Error('Download table verification failed');
  console.log('Verified release downloads, checksums, update manifest and download table.');
}

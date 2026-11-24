import { readFileSync, writeFileSync } from 'node:fs';

// Run after replacing either PNG in brand/favicons/. Embedding the artwork
// keeps the SVG self-contained for browsers that block external icon resources.
for (const theme of ['light', 'dark']) {
  const source = new URL(`../brand/favicons/${theme}.png`, import.meta.url);
  const output = new URL(`../web/favicon-${theme}.svg`, import.meta.url);
  const artwork = readFileSync(source).toString('base64');

  writeFileSync(output, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <defs>
    <clipPath id="squircle">
      <path d="M50 0 C95.45 0 100 4.55 100 50 S95.45 100 50 100 S0 95.45 0 50 S4.55 0 50 0 Z"/>
    </clipPath>
  </defs>
  <image width="100" height="100" preserveAspectRatio="xMidYMid slice" clip-path="url(#squircle)"
    href="data:image/png;base64,${artwork}"/>
</svg>
`);
}
